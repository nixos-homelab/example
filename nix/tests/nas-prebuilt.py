import json

datasets = {
    "cluster": ["k3s", "data", "torrents", "usenet"],
    "media": ["movies", "tvshows"],
}


def check_pools():
    """Every dataset is unlocked and mounted where the NAS expects it"""
    for pool, children in datasets.items():
        got = nas.succeed(f"zfs get -Ho value encryption,keyformat,keystatus {pool}").split()
        assert got == ["aes-256-gcm", "hex", "available"], (pool, got)
        for child in children:
            got = nas.succeed(f"findmnt -no SOURCE /mnt/{pool}/{child}").strip()
            assert got == f"{pool}/{child}", (child, got)


boot_prebuilt(nas)

with subtest("storage: the pools are made at the first Secure Boot, keys sealed in the credstore, before k3s starts"):
    check_pools()
    for pool in datasets:
        nas.succeed(f"test \"$(stat -c %a /etc/credstore.encrypted/{pool}.zfs-key)\" = 600")
    nas.succeed("test \"$(stat -c %a /etc/credstore.encrypted)\" = 700")
    # Ordered before local-fs.target, so k3s never wrote to the bare mountpoint
    created = "systemctl show -p ExecMainExitTimestampMonotonic --value vm-zfs-pools"
    k3s = "systemctl show -p ExecMainStartTimestampMonotonic --value k3s"
    nas.wait_until_succeeds(f"test $({k3s}) -gt 0", timeout=300)
    nas.succeed(f"test $({created}) -lt $({k3s})")

with subtest("networking: without secrets the VPNs have no keys, which only takes down their own interfaces"):
    nas.wait_for_unit("systemd-networkd.service")
    nas.wait_until_succeeds("ip -4 route show default | grep -q .")
    nas.fail("ip link show privacy-vpn")

with subtest("k3s: the node comes up dual-stack and Ready"):
    node = "k3s kubectl get node $(hostname) -o jsonpath"
    nas.wait_until_succeeds(
        f"test \"$({node}='{{.status.conditions[?(@.type==\"Ready\")].status}}')\" = True", timeout=600
    )
    # Both families, which k3s only takes with a global IPv6 address on the node
    nas.succeed(f"{node}='{{.spec.podCIDRs}}' | grep -q :")

with subtest("storage: nfs-provisioner creates a volume with the configured mode and owner"):
    # The only published image, v4.0.2, ignored NFS_DEFAULT_MODE and made every volume 0777
    try:
        nas.wait_until_succeeds(
            "k3s kubectl -n nfs-provisioner rollout status deploy/nfs-subdir-external-provisioner --timeout=10s",
            timeout=600,
        )
    except Exception:
        nas.execute(
            "k3s kubectl -n nfs-provisioner describe pods >&2; "
            "k3s kubectl -n nfs-provisioner logs deploy/nfs-subdir-external-provisioner --all-containers >&2; "
            "k3s crictl images | grep -i nfs >&2"
        )
        raise
    nas.succeed(
        "k3s kubectl apply -f - <<'EOF'\n"
        "apiVersion: v1\nkind: PersistentVolumeClaim\n"
        "metadata: {name: mode-test, namespace: default}\n"
        "spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 1Mi}}}\n"
        "EOF"
    )
    nas.wait_until_succeeds(
        "test \"$(k3s kubectl -n default get pvc mode-test -o jsonpath='{.status.phase}')\" = Bound", timeout=300
    )
    got = nas.succeed("stat -c '%a %u:%g' /mnt/cluster/data/default-mode-test").strip()
    assert got == "750 900:900", got

with subtest("networking: the host firewall opens the global ports to the LAN only, privacy-vpn's to any source"):
    ip = nas.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    # The LAN gets through once k3s listens and the policy is in place; pings are open to any source
    lan.wait_until_succeeds(f"nc -z -w 2 {ip} 6443", timeout=600)
    lan.succeed(f"nc -z -w 2 {ip} 22")
    outside.wait_until_succeeds(f"ping -c 1 -W 1 {ip}", timeout=60)
    # Cilium's host policy narrows the ports to the LAN once it's enforced; the NixOS firewall alone opens them to all
    outside.wait_until_fails(f"nc -z -w 2 {ip} 6443", timeout=120)
    outside.fail(f"nc -z -w 2 {ip} 22")
    # rtorrent's port on privacy-vpn, open to any source; nothing listens on it in the VM
    nas.succeed("k3s kubectl get ccnp host-firewall -o jsonpath='{.spec.ingress[2].toPorts[0].ports[0].port}' | grep -qx 6881")

with subtest("networking: client-vpn brings up WireGuard without SYS_MODULE"):
    # NixOS loads the module at boot. Without it the pod's `ip link add` has to load it, which needs no capability
    nas.succeed("rmmod wireguard")
    nas.wait_until_succeeds("k3s kubectl get namespace client-vpn", timeout=600)
    # Any 32 bytes make a WireGuard private key
    nas.succeed(
        "k3s kubectl -n client-vpn create secret generic client-vpn-private-keys"
        " --from-literal=admins=$(head -c 32 /dev/urandom | base64) --dry-run=client -o yaml"
        " | k3s kubectl apply -f -"
    )
    nas.wait_until_succeeds("k3s kubectl -n client-vpn rollout status deploy/admins-vpn --timeout=10s", timeout=600)
    nas.succeed("k3s kubectl -n client-vpn exec deploy/admins-vpn -- wg show clients listen-port | grep -qx 51820")
    nas.succeed("test -d /sys/module/wireguard")

with subtest("networking: cluster-wide policies: one object per name, pod-to-local-lan allows egress to the LAN"):
    lan.succeed("(nc -lk 8000 >/dev/null 2>&1 &)")
    lan_ip = lan.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    # A pod with local-lan-egress and nothing else (client-vpn's own policy allows the world), in client-vpn's image
    # for its bash
    image = nas.succeed(
        "k3s kubectl -n client-vpn get deploy admins-vpn -o jsonpath='{.spec.template.spec.containers[0].image}'"
    ).strip()
    nas.succeed(
        f"k3s kubectl -n default run lan-probe --image={image} --image-pull-policy=Never"
        " --labels=cluster.local/local-lan-egress=allow --command -- sleep 600"
    )
    nas.wait_until_succeeds("k3s kubectl -n default wait pod/lan-probe --for=condition=Ready --timeout=10s", timeout=120)
    nas.wait_until_succeeds(
        f"k3s kubectl -n default exec lan-probe -- timeout 3 bash -c 'exec 3<>/dev/tcp/{lan_ip}/8000'", timeout=60
    )
    nas.succeed("k3s kubectl get ccnp pod-to-apiserver -o jsonpath='{.spec.egress}' | grep -q kube-apiserver")
    nas.succeed("k3s kubectl get ccnp pod-from-apiserver -o jsonpath='{.spec.ingress}' | grep -q kube-apiserver")

with subtest("networking: NodePorts are served on the LAN's addresses only, not on privacy-vpn"):
    # Any key brings the interface up with its address, which is all Cilium looks at; no handshake needed
    nas.succeed(
        "mkdir -p -m 700 /etc/credstore.encrypted"
        " && head -c 32 /dev/urandom | base64 | tr -d '\\n'"
        " | systemd-creds encrypt --name=wireguard-privacy-vpn-private-key -"
        " /etc/credstore.encrypted/wireguard-privacy-vpn-private-key"
        " && systemctl restart systemd-networkd"
    )
    nas.wait_until_succeeds("ip -4 addr show privacy-vpn | grep -q 10.2.0.2", timeout=60)
    # NodePort frontends are 0.0.0.0:<port>; the node-addresses table says which addresses serve them
    addresses = "k3s kubectl -n cilium exec ds/cilium -c cilium-agent -- cilium-dbg shell -- db/show node-addresses"
    nodeport = "awk '$2 == \"true\" {print $4}'"
    nas.wait_until_succeeds(f"{addresses} | grep privacy-vpn >/dev/null", timeout=120)
    nas.succeed(f"{addresses} | {nodeport} | grep -x eth1 >/dev/null")
    nas.fail(f"{addresses} | {nodeport} | grep -x privacy-vpn >/dev/null")
    lan.succeed(f"nc -z -w 2 {ip} 9000")

with subtest("storage: the NFS exports admit loopback only"):
    # A mount of its own eth1 address comes from that address and never meets the host firewall
    nas.succeed("mkdir -p /tmp/nfs && mount -t nfs 127.0.0.2:/mnt/cluster/data /tmp/nfs && umount /tmp/nfs")
    nas.fail(f"timeout 60 mount -t nfs {ip}:/mnt/cluster/data /tmp/nfs")

with subtest("apps: postgresql has generated passwords from Secrets, the apps use them, the superuser's re-set at every start"):
    pg = "k3s kubectl -n postgresql"
    users = ["ghostfolio", "grafana", "immich"]
    for ns in ["postgresql", *users]:
        nas.wait_until_succeeds(f"k3s kubectl get namespace {ns}", timeout=600)
    # The prebuilt VM doesn't enable setup-secrets' activation and service; the NAS runs this on every deploy
    nas.succeed("setup-secrets --auto")
    secret = "k3s kubectl -n {} get secret {} -o jsonpath='{{.data.password}}' | base64 -d"
    first = nas.succeed(secret.format("postgresql", "postgres-password"))
    jwt = "k3s kubectl -n ghostfolio get secret ghostfolio-secrets -o jsonpath='{.data.JWT_SECRET_KEY}'"
    first_jwt = nas.succeed(jwt)
    assert first_jwt, "setup-secrets generated no ghostfolio-secrets"
    nas.succeed("setup-secrets --auto")
    assert nas.succeed(secret.format("postgresql", "postgres-password")) == first, "setup-secrets replaced a password"
    assert nas.succeed(jwt) == first_jwt, "setup-secrets replaced ghostfolio's JWT secret"
    for user in users:
        # The consumer's copy in its own namespace
        theirs = secret.format(user, "postgresql-password")
        nas.succeed(f"cmp <({secret.format('postgresql', user + '-password')}) <({theirs})")
    nas.wait_until_succeeds(f"{pg} rollout status deploy/postgresql --timeout=10s", timeout=600)
    # initdb's fallback of 20 connections and 400kB of buffers starves a fresh immich's index builds
    settings = nas.succeed(
        f"{pg} exec deploy/postgresql -- psql -h /run/postgresql -U postgres -tAc"
        " \"SELECT current_setting('shared_buffers') || ' ' || current_setting('max_connections')\""
    ).strip()
    assert settings == "128MB 100", settings
    for user in users:
        nas.wait_until_succeeds(f"{pg} wait job/create-{user}-db --for=condition=Complete --timeout=10s", timeout=600)

    def login(user, password_cmd):
        """Logs in over TCP to the pod's IP, which pg_hba sends to password authentication"""
        pods = f"{pg} get pod -l app.kubernetes.io/name=postgresql -o jsonpath='{{.items[*].status.podIP}}'"
        nas.wait_until_succeeds(f"test $({pods} | wc -w) = 1", timeout=120)
        ip = nas.succeed(pods).strip()
        return (
            f"{password_cmd} | {pg} exec -i deploy/postgresql -- bash -c"
            f" 'PGPASSWORD=$(cat) psql --no-psqlrc -h {ip} -U {user} -d postgres -c \"SELECT 1\"'"
        )

    for user in users:
        nas.succeed(login(user, secret.format("postgresql", user + "-password")))
        nas.fail(login(user, f"echo {user}"))
    nas.succeed(login("postgres", secret.format("postgresql", "postgres-password")))
    nas.fail(login("postgres", "echo postgres"))
    # The apps log in with their copy of the password
    for user in users:
        nas.wait_until_succeeds(f"k3s kubectl -n {user} rollout status deploy/{user} --timeout=10s", timeout=900)
    nas.succeed(f"{pg} create job backup-test --from=cronjob/backup-grafana-db")
    nas.wait_until_succeeds(f"{pg} wait job/backup-test --for=condition=Complete --timeout=10s", timeout=300)

    # An existing data dir keeps initdb's password; the restart has to set the Secret's
    nas.succeed(
        "k3s kubectl -n postgresql create secret generic postgres-password --from-literal=password=rotated"
        " --dry-run=client -o yaml | k3s kubectl apply -f -"
    )
    nas.succeed(f"{pg} rollout restart deploy/postgresql && {pg} rollout status deploy/postgresql --timeout=300s")
    nas.succeed(login("postgres", "echo rotated"))
    nas.fail(login("postgres", "echo " + first))

    # The pod's socket trusts every local connection, so no host user may reach it through the kubelet's emptyDir
    socks = nas.succeed("find /var/lib/kubelet/pods -name .s.PGSQL.5432").split()
    assert socks, "no postgresql socket under /var/lib/kubelet/pods"
    for sock in socks:
        nas.fail(f"su -s /bin/sh admin -c 'test -e {sock}'")

with subtest("apps: every workload rolls out with Ready pods, every HTTPRoute is accepted with a backend that answers"):
    # Workloads that can't come up in the VM, and why
    expected_down = {
        "external-dns/Deployment/external-dns": "no DNS provider API to reach",
        "plex/Deployment/plex": "its TLS certificate comes from ACME, and its API key Secrets from a claimed server",
    }

    def not_ready():
        """namespace/kind/name of each workload short of its desired Ready replicas"""
        items = json.loads(nas.succeed("k3s kubectl get deploy,statefulset,daemonset -A -o json"))["items"]
        down = set()
        for item in items:
            spec, status = item["spec"], item.get("status", {})
            if item["kind"] == "DaemonSet":
                want, ready = status.get("desiredNumberScheduled", 0), status.get("numberReady", 0)
            else:
                want, ready = spec.get("replicas", 1), status.get("readyReplicas", 0)
            if ready < want:
                down.add(f"{item['metadata']['namespace']}/{item['kind']}/{item['metadata']['name']}")
        return down

    try:
        retry(lambda _: not_ready() == set(expected_down), timeout_seconds=900)
    except Exception:
        down = not_ready()
        nas.execute(
            "k3s kubectl get pods -A -o wide >&2;"
            " k3s kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -50 >&2"
        )
        for workload in sorted(down - set(expected_down)):
            ns, kind, name = workload.split("/")
            nas.execute(f"k3s kubectl -n {ns} logs {kind.lower()}/{name} --all-containers --tail=40 >&2")
            nas.execute(f"k3s kubectl -n {ns} logs {kind.lower()}/{name} --all-containers --previous --tail=40 >&2")
        raise AssertionError(f"down: {sorted(down - set(expected_down))}, up: {sorted(set(expected_down) - down)}")
    routes = json.loads(nas.succeed("k3s kubectl get httproute -A -o json"))["items"]
    assert routes, "no HTTPRoutes"
    for route in routes:
        ns, name = route["metadata"]["namespace"], route["metadata"]["name"]
        conditions = {
            c["type"]: c["status"] for parent in route.get("status", {}).get("parents", []) for c in parent["conditions"]
        }
        assert conditions.get("Accepted") == "True" and conditions.get("ResolvedRefs") == "True", (ns, name, conditions)
        if any(down.startswith(f"{ns}/") for down in expected_down):
            continue
        for rule in route["spec"].get("rules", []):
            for ref in rule.get("backendRefs", []):
                ip = nas.succeed(f"k3s kubectl -n {ns} get svc {ref['name']} -o jsonpath='{{.spec.clusterIP}}'").strip()
                # Any HTTP response; 000 means nothing answered
                code = nas.succeed(
                    f"curl -s -o /dev/null -m 10 -w '%{{http_code}}' http://{ip}:{ref['port']}/ || true"
                ).strip()
                assert code not in ("", "000"), (ns, name, ref, code)
    # Some keys only exist once their app has started (SABnzbd writes its API key on first start), so like the next
    # deploy, a second run picks up what the first one in the postgresql subtest skipped
    nas.succeed("setup-secrets --auto")
    # Every Job (integrations, configuration) completes, but those that can't in the VM, and why, by name prefix (a
    # CronJob's Jobs carry the schedule time)
    expected_failed = {
        "plex/configure": "plex is down, see expected_down",
        "plex/integrate-radarr": "plex is down, see expected_down",
        "plex/integrate-sonarr": "plex is down, see expected_down",
        "ghostfolio/sync-accounts-": "needs GHOSTFOLIO_TOKEN, a token made in Ghostfolio's UI",
        "homepage/create-ghostfolio-api-token": "needs GHOSTFOLIO_TOKEN, a token made in Ghostfolio's UI",
    }

    def jobs():
        """namespace/name of each Job to complete, failed or still going"""
        items = json.loads(nas.succeed("k3s kubectl get jobs -A -o json"))["items"]
        state = {}
        for job in items:
            conditions = {c["type"]: c["status"] for c in job.get("status", {}).get("conditions", [])}
            if conditions.get("Complete") != "True":
                state[f"{job['metadata']['namespace']}/{job['metadata']['name']}"] = (
                    "failed" if conditions.get("Failed") == "True" else "running"
                )
        return state

    def expected(job):
        return any(job.startswith(prefix) for prefix in expected_failed)

    try:
        retry(lambda _: all(state != "running" or expected(job) for job, state in jobs().items()), timeout_seconds=600)
    except Exception:
        pass  # Still running after 10 minutes counts as not completing
    failed = {job for job in jobs() if not expected(job)}
    for job in sorted(failed):
        ns, name = job.split("/")
        nas.execute(f"k3s kubectl -n {ns} describe job/{name} | tail -20 >&2")
        # logs job/NAME picks its first pod; the last attempt is the one to read
        nas.execute(
            f"k3s kubectl -n {ns} logs --all-containers --tail=60"
            f" $(k3s kubectl -n {ns} get pods -l job-name={name} --sort-by=.metadata.creationTimestamp -o name | tail -1) >&2"
        )
    assert not failed, f"Jobs that didn't complete: {sorted(failed)}"

with subtest("shutdown: a reboot drains the node first, leaving no Failed pods and no cordon"):
    nas.wait_until_succeeds("k3s kubectl -n cilium rollout status deploy/cilium-operator --timeout=10s", timeout=300)
    # Through logind, which sends PrepareForShutdown; the driver's reboot() presses Ctrl+Alt+Del, which doesn't
    nas.execute("systemctl reboot >/dev/null 2>&1 &")
    nas.connected = False
    nas.wait_for_unit("multi-user.target")
    node = "k3s kubectl get node $(hostname) -o jsonpath"
    nas.wait_until_succeeds(
        f"test \"$({node}='{{.spec.unschedulable}},{{.metadata.annotations.cluster\\.local/drained-for-shutdown}}')\" = ,",
        timeout=600,
    )
    nas.fail(
        "k3s kubectl get pods -A -o jsonpath='{range .items[*]}{.status.reason}{\"\\n\"}{end}'"
        " | grep -x 'NodeShutdown\\|Terminated'"
    )
    nas.succeed("journalctl -b -1 -u k3s-drain | grep -q 'drained'")

with subtest("storage: after a reboot the pools import from the cache, keys load through the TPM, data survives"):
    nas.succeed("systemctl show -p ConditionResult --value vm-zfs-pools | grep -qx no")
    nas.succeed("systemctl is-active zfs-import-cache.service")
    for pool in datasets:
        unit = f"zfs-load-encrypted-key@{pool}.service"
        nas.succeed(f"systemctl show -p Result --value {unit} | grep -qx success")
        nas.succeed(f"test $(systemctl show -p ExecMainExitTimestampMonotonic --value {unit}) -gt 0")
        for child in datasets[pool]:
            nas.succeed(f"systemctl is-active mnt-{pool}-{child}.mount")
    check_pools()
    nas.succeed("test -d /mnt/cluster/data/default-mode-test")

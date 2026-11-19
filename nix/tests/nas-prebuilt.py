import json
import shlex

datasets = {
    "cluster": ["k3s", "data", "torrents", "usenet"],
    "media": ["movies", "tvshows"],
}


def kubectl_items(args):
    """The items of `k3s kubectl get ARGS -o json`. A read that doesn't parse is read again: one came back with bytes
    missing in the middle on a loaded host"""
    for _ in range(3):
        try:
            return json.loads(nas.succeed(f"k3s kubectl get {args} -o json"))["items"]
        except json.JSONDecodeError as e:
            error = e
    raise error


def check_pools():
    """Every dataset is unlocked and mounted where the NAS expects it"""
    for pool, children in datasets.items():
        got = nas.succeed(f"zfs get -Ho value encryption,keyformat,keystatus {pool}").split()
        assert got == ["aes-256-gcm", "hex", "available"], (pool, got)
        for child in children:
            got = nas.succeed(f"findmnt -no SOURCE /mnt/{pool}/{child}").strip()
            assert got == f"{pool}/{child}", (child, got)


boot_prebuilt(nas)
# The clients boot while k3s comes up; the first to use them is the firewall subtest
lan.start()
outside.start()

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

with subtest("k3s: the node comes up dual-stack and Ready"):
    node = "k3s kubectl get node $(hostname) -o jsonpath"
    nas.wait_until_succeeds(
        f"test \"$({node}='{{.status.conditions[?(@.type==\"Ready\")].status}}')\" = True", timeout=600
    )
    # Both families, which k3s only takes with a global IPv6 address on the node
    nas.succeed(f"{node}='{{.spec.podCIDRs}}' | grep -q :")

with subtest("networking: the host firewall opens the global ports to the LAN only, privacy-vpn's to any source"):
    ip = nas.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    # The LAN gets through once k3s listens and the policy is in place; pings are open to any source
    lan.wait_until_succeeds(f"nc -z -w 2 {ip} 6443", timeout=600)
    lan.succeed(f"nc -z -w 2 {ip} 22")
    outside.wait_until_succeeds(f"ping -c 1 -W 1 {ip}", timeout=60)
    # Cilium's host policy narrows the ports to the LAN once it's enforced; the NixOS firewall alone opens them to all.
    # On a public runner k3s may still be applying the manifests minutes after the LAN gets through
    outside.wait_until_fails(f"nc -z -w 2 {ip} 6443", timeout=600)
    outside.fail(f"nc -z -w 2 {ip} 22")
    # rtorrent's port on privacy-vpn, open to any source; nothing listens on it in the VM
    nas.succeed("k3s kubectl get ccnp host-firewall -o jsonpath='{.spec.ingress[2].toPorts[0].ports[0].port}' | grep -qx 6881")

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
    # The NodePort of k8sss, which answers once step-ca is Ready; nothing above waits for that, and this early in the
    # suite the cluster is still coming up: minutes on a public runner
    lan.wait_until_succeeds(f"nc -z -w 2 {ip} 9000", timeout=900)

with subtest("storage: the NFS exports admit loopback only"):
    # A mount of its own eth1 address comes from that address and never meets the host firewall
    nas.succeed("mkdir -p /tmp/nfs && mount -t nfs 127.0.0.2:/mnt/cluster/data /tmp/nfs && umount /tmp/nfs")
    nas.fail(f"timeout 60 mount -t nfs {ip}:/mnt/cluster/data /tmp/nfs")

with subtest("apps: the apps get their PostgreSQL passwords and databases, log in and hold their schemas"):
    pg = "k3s kubectl -n postgresql"
    # Grafana's is off with the monitoring stack, see nas-prebuilt.nix
    users = ["forgejo", "ghostfolio", "immich", "prowlarr", "radarr", "sonarr"]
    # Each with a second database of the same user, for its log
    servarr = ["prowlarr", "radarr", "sonarr"]
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
    # Available, not `rollout status`: the pods waited for the Secrets setup-secrets makes above, which on a slow host
    # comes after the Deployments' 10 minutes of progress deadline, and past that `rollout status` only fails
    available = "wait deploy/{} --for=condition=Available --timeout=10s"
    nas.wait_until_succeeds(f"{pg} {available.format('postgresql')}", timeout=600)
    for db in users + [f"{app}-log" for app in servarr]:
        nas.wait_until_succeeds(f"{pg} wait job/create-{db}-db --for=condition=Complete --timeout=10s", timeout=600)

    # The apps log in with their copy of the password
    for user in users:
        try:
            nas.wait_until_succeeds(f"k3s kubectl -n {user} {available.format(user)}", timeout=900)
        except Exception:
            nas.execute(
                f"k3s kubectl -n {user} describe pods | tail -40 >&2;"
                f" k3s kubectl -n {user} logs deploy/{user} --all-containers --previous --tail=60 >&2;"
                f" k3s kubectl -n {user} logs deploy/{user} --all-containers --tail=60 >&2"
            )
            raise
    # Both databases of each app hold its schema, the log database a hyphen in its name
    for app in servarr:
        for db in [app, f"{app}-log"]:
            nas.succeed(
                f"{pg} exec deploy/postgresql -- psql -h /run/postgresql -U postgres -d {db} -tAc"
                " 'SELECT 1 FROM \"VersionInfo\" LIMIT 1' | grep -qx 1"
            )

with subtest("apps: docs serves the site with the system's values to pods with cluster egress, and no other pod"):
    nas.wait_until_succeeds("k3s kubectl -n docs get certificate docs", timeout=600)
    # Its certificate comes from ACME, which the VM can't reach: a self-signed issuer stands in
    nas.succeed(
        "k3s kubectl apply -f - <<'EOF'\n"
        "apiVersion: cert-manager.io/v1\nkind: ClusterIssuer\nmetadata: {name: selfsigned}\nspec: {selfSigned: {}}\n"
        "EOF"
    )
    nas.succeed(
        "k3s kubectl -n docs patch certificate docs --type=merge -p '{\"spec\":{\"issuerRef\":{\"name\":\"selfsigned\"}}}'"
    )
    nas.wait_until_succeeds("k3s kubectl -n docs get secret docs-tls", timeout=300)
    nas.wait_until_succeeds("k3s kubectl -n docs rollout status deploy/docs --timeout=10s", timeout=600)
    ip = nas.wait_until_succeeds(
        "k3s kubectl -n docs get svc docs-external -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | grep .",
        timeout=120,
    ).strip()
    # awk reads crictl's output to the end: an early exit would kill crictl with SIGPIPE, and pipefail fail the command
    utils = nas.succeed(
        "k3s crictl images | awk '$1 == \"cluster.local/utils\" && !found { print $1 \":\" $2; found = 1 }'"
    ).strip()
    assert utils, "no cluster.local/utils image"
    probe = "trap exit TERM; sleep 600 & wait"
    nas.succeed(
        f"k3s kubectl -n default run docs-probe --image={utils} --image-pull-policy=Never"
        f" --labels=cluster.local/cluster-egress=allow --command -- bash -c '{probe}'"
    )
    nas.succeed(f"k3s kubectl -n default run docs-stranger --image={utils} --image-pull-policy=Never --command -- bash -c '{probe}'")
    nas.wait_until_succeeds(
        "k3s kubectl -n default wait pod/docs-probe pod/docs-stranger --for=condition=Ready --timeout=10s", timeout=120
    )
    # The domain is set on this system, so its row carries the value, marked changed
    page = nas.wait_until_succeeds(
        f"k3s kubectl -n default exec docs-probe -- curl -sfk -m 10 https://{ip}/shared/options/workloads/", timeout=60
    )
    row = page[page.index('id="homelab.workloads.domain"'):]
    # Cell values carry break points (<wbr>) at their dots
    row = row[: row.index("</tr>")].replace("<wbr>", "")
    assert "nd-value nd-changed" in row and "example.org" in row, row
    nas.fail(f"k3s kubectl -n default exec docs-stranger -- curl -sfk -m 5 https://{ip}/")
    nas.succeed("k3s kubectl -n default delete pod docs-probe docs-stranger --wait=false")

with subtest("apps: every workload rolls out with Ready pods, every HTTPRoute is accepted with a backend that answers"):
    # admins-vpn needs its WireGuard key, which setup-secrets asks for; any 32 bytes make one. What client-vpn does with
    # it is networking's own test
    nas.wait_until_succeeds("k3s kubectl get namespace client-vpn", timeout=600)
    nas.succeed(
        "k3s kubectl -n client-vpn create secret generic client-vpn-private-keys"
        " --from-literal=admins=$(head -c 32 /dev/urandom | base64) --dry-run=client -o yaml"
        " | k3s kubectl apply -f -"
    )
    # Workloads that can't come up in the VM, and why
    expected_down = {
        "external-dns/Deployment/external-dns": "no DNS provider API to reach",
        "plex/Deployment/plex": "its TLS certificate comes from ACME, and its API key Secrets from a claimed server",
    }

    def not_ready():
        """namespace/kind/name of each workload short of its desired Ready replicas"""
        items = kubectl_items("deploy,statefulset,daemonset -A")
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
    routes = kubectl_items("httproute -A")
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
        items = kubectl_items("jobs -A")
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

with subtest("development: Forgejo's admin logs in, a repo takes pushes over HTTP and over SSH on its Gateway's port 22"):
    fj = "k3s kubectl -n forgejo"
    password = nas.succeed(f"{fj} get secret forgejo-secrets -o jsonpath='{{.data.ADMIN_PASSWORD}}' | base64 -d")
    # Over HTTP to the Service: in the VM Envoy answers every request through a Gateway with 403 (Cilium denies it)
    web = nas.succeed(f"{fj} get svc forgejo -o jsonpath='{{.spec.clusterIP}}'").strip() + ":3000"
    curl = f"curl -sf -u forgejo-admin:{password} -H 'Content-Type: application/json'"
    api = f"http://{web}/api/v1"
    assert json.loads(nas.succeed(f"{curl} {api}/user"))["login"] == "forgejo-admin"
    nas.succeed(f"{curl} -X POST -d '{{\"name\":\"test\"}}' {api}/user/repos")
    git = "git -C /tmp/repo -c user.name=test -c user.email=test@example.org"

    def pushed(_):
        """Whether the forge's main is the local HEAD, which it records after the push returns"""
        status, branch = nas.execute(f"{curl} {api}/repos/forgejo-admin/test/branches/main")
        head = nas.succeed(f"{git} rev-parse HEAD").strip()
        return status == 0 and json.loads(branch)["commit"]["id"] == head

    nas.succeed(
        f"git init -q -b main /tmp/repo && {git} commit -q --allow-empty -m http"
        f" && {git} push -q http://forgejo-admin:{password}@{web}/forgejo-admin/test.git main"
    )
    retry(pushed, timeout_seconds=60)
    # The TCPRoute: Cilium balances port 22 of the Gateway's address to the built-in SSH server, past Envoy
    addresses = nas.succeed(f"{fj} get gateway forgejo -o jsonpath='{{.status.addresses[*].value}}'").split()
    ip = next(a for a in addresses if ":" not in a)
    nas.succeed("ssh-keygen -q -t ed25519 -N '' -f /tmp/forgejo-ssh")
    key = json.dumps({"title": "test", "key": nas.succeed("cat /tmp/forgejo-ssh.pub").strip()})
    nas.succeed(f"{curl} -X POST -d {shlex.quote(key)} {api}/user/keys")
    ssh = "ssh -i /tmp/forgejo-ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    nas.succeed(
        f"{git} commit -q --allow-empty -m ssh"
        f" && GIT_SSH_COMMAND='{ssh}' {git} push -q git@{ip}:forgejo-admin/test.git main"
    )
    retry(pushed, timeout_seconds=60)

with subtest("shutdown: a reboot drains the node first, leaving no Failed pods and no cordon"):
    # What has to survive the reboot on the cluster pool
    nas.succeed("touch /mnt/cluster/data/reboot-marker")
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
    nas.succeed("test -f /mnt/cluster/data/reboot-marker")


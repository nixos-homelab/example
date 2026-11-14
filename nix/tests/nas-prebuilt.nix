{ lib, hostPkgs, ... }:
let
  client = {
    nixpkgs.hostPlatform = hostPkgs.stdenv.hostPlatform.system;
    environment.systemPackages = [ hostPkgs.netcat ];
  };
in
{
  # The host firewall's LAN is the test VLAN's lower half: lan and the nas get .1 and .2, outside sits above it
  nodes.nas.homelab.cilium.cidr-groups.localLANCIDR4 = lib.mkForce "192.168.1.0/25";
  # The CPUs of a public runner, or up to 8 on a host with more: the last -smp counts. More vCPUs than the host has
  # stall the guest under nested KVM
  nodes.nas.virtualisation.cores = lib.mkForce 4;
  nodes.nas.virtualisation.qemu.options = [
    "-smp $(n=$(${hostPkgs.coreutils}/bin/nproc); echo $((n < 8 ? n : 8)))"
  ];
  # Manifests that a later generation no longer has, which the k3s subtests link into k3s' manifests directory. The
  # first also declares an object of a manifest k3s bundles, as one that moved to a remaining manifest
  nodes.nas.environment.etc."k3s-prune-test/prune-test.yaml".text = ''
    apiVersion: v1
    kind: ConfigMap
    metadata: {name: prune-test, namespace: default}
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata: {name: kube-apiserver-kubelet-admin}
    roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: "system:kubelet-api-admin"}
    subjects: [{apiGroup: rbac.authorization.k8s.io, kind: User, name: kube-apiserver}]
  '';
  nodes.nas.environment.etc."k3s-prune-test/prune-test-boot.yaml".text = ''
    apiVersion: v1
    kind: ConfigMap
    metadata: {name: prune-test-boot, namespace: default}
  '';
  nodes.lan = lib.mkMerge [
    client
    # For the pods allowed to reach the LAN
    { networking.firewall.allowedTCPPorts = [ 8000 ]; }
  ];
  nodes.outside = lib.mkMerge [
    client
    {
      networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
        {
          address = "192.168.1.200";
          prefixLength = 24;
        }
      ];
    }
  ];
}

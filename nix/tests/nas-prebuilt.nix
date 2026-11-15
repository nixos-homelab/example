{ lib, hostPkgs, ... }:
let
  client = {
    nixpkgs.hostPlatform = hostPkgs.stdenv.hostPlatform.system;
    # netcat is all they run
    virtualisation.memorySize = 512;
    environment.systemPackages = [ hostPkgs.netcat ];
  };
in
{
  # The host firewall's LAN is the test VLAN's lower half: lan and the nas get .1 and .2, outside sits above it
  nodes.nas.homelab.cilium.cidr-groups.localLANCIDR4 = lib.mkForce "192.168.1.0/25";
  # The CPUs of the host but one, up to 8: the last -smp counts. More vCPUs than the host has stall the guest under
  # nested KVM, and all of them starve the runner's own agent, which then loses its connection to GitHub
  nodes.nas.virtualisation.cores = lib.mkForce 3;
  nodes.nas.virtualisation.qemu.options = [
    "-smp $(n=$(${hostPkgs.coreutils}/bin/nproc); n=$((n > 1 ? n - 1 : 1)); echo $((n < 8 ? n : 8)))"
  ];
  # A client of the forge for the Forgejo subtest
  nodes.nas.environment.systemPackages = [ hostPkgs.git ];
  # The disks of the pools last only as long as the test, so QEMU skips the flushes of ZFS and containerd
  nodes.nas.imports = [
    (
      { config, ... }:
      {
        virtualisation.qemu.options = lib.concatLists (
          lib.imap1 (
            idx: drive: lib.optional (lib.hasInfix "/empty" drive.file) "-set drive.drive${toString idx}.cache=unsafe"
          ) config.virtualisation.qemu.drives
        );
      }
    )
  ];
  nodes.lan = client;
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

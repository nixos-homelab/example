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
  # The CPUs of a public runner, or up to 8 on a host with more: the last -smp counts. More vCPUs than the host has
  # stall the guest under nested KVM
  nodes.nas.virtualisation.cores = lib.mkForce 4;
  nodes.nas.virtualisation.qemu.options = [
    "-smp $(n=$(${hostPkgs.coreutils}/bin/nproc); echo $((n < 8 ? n : 8)))"
    # See the watchdog below
    "-device i6300esb"
    "-action watchdog=poweroff"
  ];
  # The monitoring stack (Alloy, Loki, Mimir, the exporters, Grafana, which doesn't start without them) doubled the suite's
  # time on a public runner's 4 CPUs, past an hour; monitoring is the repo to test it
  nodes.nas.homelab = {
    alloy.enable = lib.mkForce false;
    grafana.enable = lib.mkForce false;
    loki.enable = lib.mkForce false;
    mimir.enable = lib.mkForce false;
    node-exporter.enable = lib.mkForce false;
    smartctl-exporter.enable = lib.mkForce false;
    zfs-exporter.enable = lib.mkForce false;
  };
  # A guest that panics stops petting the watchdog and QEMU powers it off, which fails the test at once; without it the
  # driver waits on the dead guest until the job's timeout
  nodes.nas.boot.kernelModules = [ "i6300esb" ];
  nodes.nas.systemd.settings.Manager.RuntimeWatchdogSec = "2min";
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

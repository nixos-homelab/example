{ self, ... }:
{ lib, config, ... }:
{
  # Every nixosConfiguration that runs the NAS, on real hardware or in a VM
  imports = self.lib.importsApply [
    ../../base.nix
    ./zfs.nix
    ./cluster.nix
    ./networking.nix
    ./storage.nix
    ./workloads.nix
  ];
  options.nas.ipv6Prefix = lib.mkOption {
    description = "The /64 the pod, service and load balancer ranges of the cluster come from, without the trailing ::.";
    type = lib.types.str;
  };
  config = {
    system.stateVersion = "26.05";
    systemd.repart.partitions = {
      "10-esp".UUID = "98cdf820-2dab-4bed-8062-61d1f2cfea9c";
      "20-root" = {
        Label = "nixos-nas";
        UUID = "d7373674-b5b9-4580-aaba-3dcd0de2d006";
      };
    };
    hardware.cpu.amd.updateMicrocode = config.hardware.enableRedistributableFirmware;
    nixpkgs.config.allowUnfreePredicate =
      pkg:
      lib.elem (lib.getName pkg) [
        "mongodb"
        "plexmediaserver"
        "unifi-controller"
        "unrar"
      ];
  };
}

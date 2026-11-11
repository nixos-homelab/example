{ self, inputs, ... }:
{
  pkgs,
  lib,
  ...
}:
{
  # The NAS itself
  imports =
    with inputs.hardware.nixosModules;
    [
      common-pc-ssd
      common-cpu-amd
      common-cpu-amd-pstate
    ]
    ++ self.lib.importsApply [
      ../../profiles/role/nas
      ../../profiles/target/physical-machine.nix
    ];
  config = {
    networking.hostName = "nas";
    networking.domain = "example.org";
    homelab.cluster.domain = "example.org";
    boot.kernelParams = [ "consoleblank=60" ];
    boot.kernelModules = [ "kvm-amd" ];
    environment.systemPackages = [ pkgs.smartmontools ];
    # Spin the hard disks down after 10 minutes without access
    services.udev.extraRules = lib.concatStringsSep ", " [
      ''ACTION=="add|change"''
      ''SUBSYSTEM=="block"''
      ''KERNEL=="sd[a-z]"''
      ''ATTR{queue/rotational}=="1"''
      ''RUN+="${lib.getExe pkgs.hdparm} -B 127 -S 120 /dev/%k"''
    ];
  };
}

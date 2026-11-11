{ self, inputs, ... }:
{ ... }:
{
  # A VM that boots an installer ISO onto a blank disk
  imports = [ inputs.sbfde.nixosModules.vm ] ++ self.lib.importsApply [ ../all.nix ];
  config.system.stateVersion = "26.05";
  config.virtualisation.fileSystems."/" = {
    fsType = "ext4";
    device = "/dev/disk/by-partlabel/nixos";
  };
}

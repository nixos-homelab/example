{ self, inputs, ... }:
{ modulesPath, ... }:
{
  # An installer ISO
  imports = self.lib.importsApply [ ../all.nix ] ++ [
    inputs.sbfde.nixosModules.installer
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
  ];
  config = {
    system.stateVersion = "26.05";
    networking.hostName = "installer";
    sbfde.installer = {
      enable = true;
      # Yours. A private repository also needs a deployKey that can read it
      repoUrl = "github:nixos-homelab/example";
    };
  };
}

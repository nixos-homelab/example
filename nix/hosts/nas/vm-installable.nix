{ self, ... }:
{ ... }:
{
  # The NAS in a VM, installed by the unattended installer
  imports = self.lib.importsApply [
    ../../profiles/role/nas
    ../../profiles/target/vm-installable.nix
  ];
  config = {
    networking.hostName = "nas-vm-install";
    networking.domain = "installable.example.org";
    homelab.cluster.domain = "installable.example.org";
  };
}

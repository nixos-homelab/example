{ self, ... }:
{ ... }:
{
  # A test instance in a VM, installed with the sbfde installer
  imports = self.lib.importsApply [
    ../substrate/vm.nix
    ../provisioning/installed.nix
    ./test.nix
  ];
  config.nas.ipv6Prefix = "2001:db8:1234:fe80";
}

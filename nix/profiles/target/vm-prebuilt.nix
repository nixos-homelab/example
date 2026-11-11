{ self, ... }:
{ ... }:
{
  # A test instance in a VM, from a prebuilt disk image
  imports = self.lib.importsApply [
    ../substrate/vm.nix
    ../provisioning/prebuilt.nix
    ./test.nix
  ];
  config.nas.ipv6Prefix = "2001:db8:1234:fe81";
}

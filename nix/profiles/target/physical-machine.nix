{ self, ... }:
{ ... }:
{
  # The NAS itself, on real hardware
  imports = self.lib.importsApply [
    ../substrate/physical.nix
    ../provisioning/installed.nix
  ];
  config = {
    # A password that unlocks the disk when the TPM won't, after a firmware update for instance
    sbfde.enrollFallbackPassword = true;
    nas.ipv6Prefix = "2001:db8:1234:cafe";
  };
}

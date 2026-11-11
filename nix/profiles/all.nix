{ ... }:
{ ... }:
{
  # Every nixosConfiguration, the installers included
  config = {
    time.timeZone = "UTC";
    nixpkgs.hostPlatform = "x86_64-linux";
    boot.zfs.forceImportRoot = false;
  };
}

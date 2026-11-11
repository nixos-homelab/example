{ inputs, ... }:
{ ... }:
{
  # A machine whose disk image is built directly, without the installer. Only with substrate/vm.nix: the image is a
  # QEMU disk
  imports = [ inputs.qemu-vm.nixosModules.qemuSetup ];
  config = {
    boot.growPartition = true;
    systemd.repart.partitions."20-root".Encrypt = false;
    virtualisation = {
      diskSize = 50 * 1024;
      fileSystems."/".autoResize = true;
    };
  };
}

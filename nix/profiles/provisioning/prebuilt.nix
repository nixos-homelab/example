{ inputs, ... }:
{ ... }:
{
  # A machine whose disk image is built directly, without the installer. Only with substrate/vm.nix: the image is a
  # QEMU disk
  imports = [ inputs.qemu-vm.nixosModules.qemuSetup ];
  config = {
    boot.growPartition = true;
    # The image carries every image archive, and its first boot imports them all
    homelab.k3s.zstdImages = true;
    systemd.repart.partitions."20-root".Encrypt = false;
    virtualisation = {
      diskSize = 50 * 1024;
      fileSystems."/".autoResize = true;
    };
  };
}

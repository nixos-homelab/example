{ inputs, ... }:
{ ... }:
{
  # What a machine running as a QEMU guest needs
  imports = [ inputs.qemu-vm.nixosModules.qemuGuest ];
}

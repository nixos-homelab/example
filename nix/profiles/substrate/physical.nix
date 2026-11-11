{ ... }:
{ ... }:
{
  # What a machine on real hardware needs
  config = {
    hardware.enableRedistributableFirmware = true;
    boot.initrd.availableKernelModules = [
      "ahci"
      "xhci_pci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
  };
}

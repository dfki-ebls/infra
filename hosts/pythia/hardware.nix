# ASUS Pro WS WRX90E-SAGE SE, AMD Threadripper PRO 9975WX, 8x 32 GB DDR5-6400 ECC,
# 2x RTX PRO 6000 Blackwell Workstation Edition, RTX PRO 6000 Blackwell Max-Q Workstation Edition.
{ ... }:
{
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];

  # Passthrough DMA for the RTX PRO 6000's tensor-parallel peer-to-peer
  # transfers, which CUDA does not support under a translating IOMMU on bare
  # metal, risking silent memory corruption.
  # https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting/gpu_troubleshooting.html#linux-bare-metal-iommu-and-pcie-peer-to-peer
  boot.kernelParams = [ "iommu=pt" ];

  hardware.enableAllFirmware = true;

  # Logs corrected and uncorrected ECC memory errors.
  hardware.rasdaemon.enable = true;
}

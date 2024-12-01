{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "usb_storage" ];
  boot.kernelModules = [ "kvm-amd" "sg" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."encryptedRoot" = {
    keyFileSize = 4096;
    keyFile = lib.mkForce"/dev/disk/by-id/usb-SMI_USB_DISK-0:0";
    # This allows for password fallout, otherwise it times out and boots into recovery
    keyFileTimeout = 5;
  };

  hardware.graphics.enable32Bit = true;
  boot.initrd.luks.devices."encryptedHome" = { 
    keyFileSize = 4096;
    keyFile = lib.mkForce"/dev/disk/by-id/usb-SMI_USB_DISK-0:0";
    # This allows for password fallout, otherwise it times out and boots into recovery
    keyFileTimeout = 5;
  };

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp4s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

{ pkgs, config, lib, ... }: {

  options = {
    virt-manager.enable = lib.mkEnableOption "enables virt-manager and libvirtd";
  };

  config = lib.mkIf config.virt-manager.enable {

    # Disable BTRFS CoW on libvirt images to avoid double-CoW with qcow2
    # and eliminate wasted CPU on zstd compression of VM disk data.
    systemd.tmpfiles.rules = [
      "d /var/lib/libvirt/images 0711 root root -"
    ];

    systemd.services.libvirt-nocow = {
      description = "Disable BTRFS CoW on libvirt images directory";
      wantedBy = [ "libvirtd.service" ];
      before = [ "libvirtd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.e2fsprogs}/bin/chattr +C /var/lib/libvirt/images";
      };
      unitConfig.ConditionPathIsDirectory = "/var/lib/libvirt/images";
    };

    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
        	# ovmf = {
          #   enable = true;
          #   packages = [pkgs.OVMFFull.fd];
          # };
        	swtpm.enable = true;
        };
      };
      spiceUSBRedirection.enable = true;
    };

    services.spice-vdagentd.enable = true;

    boot.extraModprobeConfig = "options kvm_intel nested=1";

    environment.sessionVariables.LIBVIRT_DEFAULT_URI = [ "qemu:///system" ];
    environment.systemPackages = with pkgs; [
      spice
      virt-manager
      virtio-win
      virt-viewer
      spice-gtk
      win-spice
      spice-protocol
      bridge-utils
      quickemu
    ];
    users.users.alex = {
      extraGroups = [ "libvirtd" "kvm" "qemu-libvirtd" ];
    };

    # Post Installation steps include starting the default networking automatically on boot with:
    # virsh net-autostart default

    environment.etc = {
      "ovmf/edk2-x86_64-secure-code.fd" = {
        source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-x86_64-secure-code.fd";
      };

      "ovmf/edk2-i386-vars.fd" = {
        source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-i386-vars.fd";
      };
    };
  };
}

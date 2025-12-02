{pkgs, config, ...}: {

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
}
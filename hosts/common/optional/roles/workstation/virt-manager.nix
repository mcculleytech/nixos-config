{pkgs, config, ...}: {

    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
        	ovmf = {
            enable = true;
            packages = [pkgs.OVMFFull.fd];
          };
        	swtpm.enable = true;
        };
      };
    };

    environment.sessionVariables.LIBVIRT_DEFAULT_URI = [ "qemu:///system" ];
    environment.systemPackages = with pkgs; [ 
      spice 
      virt-manager 
      win-virtio
      virt-viewer
      spice-gtk
      win-spice
      spice-protocol
      bridge-utils
    ];
    users.users.alex = {
      extraGroups = [ "libvirtd" "kvm" "qemu-libvirtd" ];
    };

    # Post Installation steps include starting the default networking automatically on boot with:
    # virsh net-autostart default
}
{pkgs, ...}: {

    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
        	ovmf.enable = true;
        	swtpm.enable = true;
        };
      };
    };

    environment.sessionVariables.LIBVIRT_DEFAULT_URI = [ "qemu:///system" ];
    environment.systemPackages = with pkgs; [ spice virt-manager win-virtio (OVMFFull.override{
    	secureBoot = true;
    	tpmSupport = true;
    }).fd];
    users.users.alex = {
      extraGroups = [ "libvirtd" "kvm" "qemu-libvirtd" ];
    };
	
}
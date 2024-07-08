{pkgs, config, ...}: {

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


    environment.etc = {
      "ovmf/edk2-x86_64-secure-code.fd" = {
        source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-x86_64-secure-code.fd";
      };

      "ovmf/edk2-i386-vars.fd" = {
        source = config.virtualisation.libvirtd.qemu.package + "/share/qemu/edk2-i386-vars.fd";
      };
    };

    systemd.services.virt-network-start = {
         wantedBy = [ "multi-user.target" ];
         after = [ "network.target" ];
         description = "start default virt network NAT";
         serviceConfig = {
           Type = "simple";
           ExecStart = "${pkgs.libvirt}/bin/virsh net-start default"; 
         };
      };
	
}
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
    ];
    users.users.alex = {
      extraGroups = [ "libvirtd" "kvm" "qemu-libvirtd" ];
    };

    systemd.services.virt-network-start = {
         wantedBy = [ "multi-user.target" ];
         after = [ "libvirtd.service" ];
         description = "start default virt network NAT";
         serviceConfig = {
           Type = "oneshot";
           ExecStart = "${pkgs.libvirt}/bin/virsh net-start default";
           RemainAfterExit = true; 
           Restart = "no";
         };
      };
	
}
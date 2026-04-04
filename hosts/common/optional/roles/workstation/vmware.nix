{ inputs, config, pkgs, lib, ... }: {

  options = {
    vmware.enable = lib.mkEnableOption "enables VMware Workstation";
  };

  config = lib.mkIf config.vmware.enable {
    # This will requireFile - Download the bundle from Broadcom and add to nix store before rebuild for updates.
    virtualisation.vmware.host = {
      enable = true;
      package = pkgs.unstable.vmware-workstation;
      extraConfig = ''
        prefvmx.minVmMemPct = "100"
      '';
    };
  };
}

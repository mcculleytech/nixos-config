{ pkgs, config, lib, ... }: {

  # Create the option for the service
  options = {
    SERVICE.enable =
      lib.mkEnableOption "enables SERVICE";
  };

  # Creates the 'if' statement for service.
  config = lib.mkIf config.SERVICE.enable {

    # Configure Actual Service here
    services.SERVICE = {
    };

    # If needed.
    # networking.firewall.allowedTCPPorts = [ ];

    # If needed.
    # environment.persistence = {
    #   "/persist" = {
    #   hideMounts = true;
    #     directories = [
    #       "/var/lib/SERVICE"
    #     ];
    #   };
    # };
    
  };

}

{ lib, inputs, config, ... }: {

 	options = {
		home-impermanence.enable =
			lib.mkEnableOption "enables home-impermanence, primary use case for servers.";
	};


	config = lib.mkIf config.home-impermanence.enable {

	environment.persistence."/persist" = {
	    enable = true;  # NB: Defaults to true, not needed
	    hideMounts = true;
	    users.alex = {
	      directories = [
	        "Downloads"
	        "Documents"
	        "Repositories"
	        { directory = ".gnupg"; mode = "0700"; }
	        { directory = ".ssh"; mode = "0700"; }
	        { directory = ".nixops"; mode = "0700"; }
	        { directory = ".local"; mode = "0700"; }
	        { directory = ".config"; mode = "0700"; }
	      ];
	      files = [
	        ".bash_history"
	      ];
	    };
	  };
	};

}
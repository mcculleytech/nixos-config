{
	services.xonotic = {
		enable = true;

		settings ={
			sv_public = 0;
			sv_motd = "Et Verbum Carum Factum Est";
			hostname = "harkonnen (ver $g_xonoticversion)";
		};
		openFirewall = true;
	};

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/xonotic"
	    ];
	  };
	};
}
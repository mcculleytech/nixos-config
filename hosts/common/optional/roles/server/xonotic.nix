{

	options = {
		xonotic.enable =
			lib.mkEnableOption "enables xonotic server";
	};

	config = lib.mkIf config.xonotic.enable {

	services.xonotic = {
		enable = true;
		settings ={
			sv_public = -1;
			sv_motd = "Et Verbum Carum Factum Est";
			hostname = "vader (ver $g_xonoticversion)";
			bot_prefix = "[BOT]";
			gametype = "tdm";
			sv_vote_gametype = 1;
			g_maplist_votable = 4;
			skill = 3;
			maxplayers = 8;
			sv_status_privacy = 1;
			minplayers_per_team = 4;
			minplayers = 8;
			bot_vs_human = 2;
			alias = ''bots "minplayers 4; minplayers_per_team 2"'';
		};
		openFirewall = true;
	};

	};
}
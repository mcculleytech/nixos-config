{
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
			maxplayers = 6;
			sv_status_privacy = 1;
			minplayers_per_team = 3;
		};
		openFirewall = true;
	};
}
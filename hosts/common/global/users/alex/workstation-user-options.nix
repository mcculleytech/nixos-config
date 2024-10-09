{config, pkgs, lib, ...}:

{
	options = {
		workstation-user-options.enable =
			lib.mkEnableOption "sets user specific workstation options";
	};

	config = lib.mkIf config.workstation-user-options.enable {
		programs.zsh.enable = true;
		users.users.alex.shell = pkgs.zsh;
	};
}
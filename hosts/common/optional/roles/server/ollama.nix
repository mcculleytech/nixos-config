{ pkgs, config, lib, ... }: {

  options = {
    ollama.enable =
      lib.mkEnableOption "enables ollama server";
  };

  config = lib.mkIf config.ollama.enable {

    # ─── Fixed user instead of DynamicUser ──────────────────────────────────
    # The default DynamicUser pattern stores data at /var/lib/private/ollama
    # which lives on encryptedRoot (the 233GB system disk) and gets crowded
    # by /nix store + container images. With a fixed `ollama` system user we
    # can relocate `home` and `models` to /home (encryptedHome, 932GB, not
    # subject to impermanence) where the 26GB of model weights have room to
    # breathe. Predictable uid also means existing files don't need a chown
    # dance on every boot.
    users.users.ollama = {
      isSystemUser = true;
      group = "ollama";
      home = "/home/ollama";
      description = "ollama LLM server";
    };
    users.groups.ollama = { };

    services.ollama = {
      package = pkgs.unstable.ollama-cuda.override {
        cudaArches = [ "61" ];
      };
      enable = true;
      acceleration = "cuda";
      host = "0.0.0.0";
      port = 11434;
      user = "ollama";
      group = "ollama";
      home = "/home/ollama";
      models = "/home/ollama/models";
      environmentVariables = { };
    };

    systemd.tmpfiles.rules = [
      "d /home/ollama 0700 ollama ollama -"
      "d /home/ollama/models 0700 ollama ollama -"
      # Z = recursive chown — fixes ownership on first activation (rsync'd
      # files inherit old DynamicUser uid which doesn't exist anymore).
      # Subsequent runs are no-ops once ownership matches.
      "Z /home/ollama 0700 ollama ollama -"
    ];

    # The upstream ollama module sets `ProtectHome=true` to deny any access
    # to /home — sensible default but it blocks our relocated home path
    # from being usable. Override with BindPaths to selectively expose
    # /home/ollama; everything else under /home stays hidden from ollama's
    # mount namespace. PrivateUsers also gets disabled because its uid
    # mapping breaks ownership checks against a real (non-dynamic) user.
    systemd.services.ollama.serviceConfig = {
      ProtectHome = lib.mkForce "tmpfs";
      BindPaths = [ "/home/ollama" ];
      PrivateUsers = lib.mkForce false;
    };

    # No /persist persistence — /home is on encryptedHome and persists
    # natively (not impermanent). Same pattern as the podman storage move.
  };

}

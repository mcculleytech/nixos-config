{ config, lib, pkgs, ... }:
let
  cfg = config.lab.protonmail-bridge;
in
{
  # ─── Headless Proton Mail Bridge ─────────────────────────────────────────
  # Wraps the upstream nixpkgs `services.protonmail-bridge` module (which is
  # graphical-session bound) and tweaks it for headless server operation:
  #   • Override wantedBy → default.target so it runs at boot, not at login
  #   • Enable `linger` on the operator user so their systemd-user manager
  #     runs at boot regardless of whether they ever log in
  #
  # No GPG/pass/keyring backend required. Bridge has a built-in `insecure`
  # file backend (encrypted vault keyed off machine identity) that activates
  # automatically when no Secret Service is available. The vault lives at
  # `~/.config/protonmail/bridge-v3/insecure/vault.enc`. Threat model is the
  # same as any service that stores credentials on disk — encrypted at the
  # LUKS layer (encryptedRoot), Bridge's per-IMAP-client token is a separate
  # credential from Proton account login (revocable from Proton web UI),
  # and Proton 2FA on the account is the real backstop.
  #
  # Exposes loopback only (Bridge picked the +1 ports because 1143/1025 had
  # stale TIME_WAIT holds during the 2026-05-26 bootstrap, and it persists the
  # choice in its vault):
  #   127.0.0.1:1144 — IMAP (STARTTLS, self-signed)
  #   127.0.0.1:1026 — SMTP submission (STARTTLS + AUTH)
  # email-mcp on saruman connects to these (EMAIL_MCP_IMAP_ADDR/SMTP_ADDR).
  options.lab.protonmail-bridge = {
    enable = lib.mkEnableOption ''
      headless Proton Mail Bridge, autostart at boot via user-linger
    '';

    user = lib.mkOption {
      type = lib.types.str;
      default = "alex";
      description = ''
        UNIX user that owns the Bridge vault under ~/.config/protonmail.
        Must be the same user who completed the one-time `bridge login`
        bootstrap — Bridge's vault is keyed to a per-installation derived
        key, so switching users invalidates the existing vault.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # System-side dbus + PAM wiring for gnome-keyring. The actual daemon
    # runs as a user service (below); this just registers the dbus name.
    services.gnome.gnome-keyring.enable = true;

    # Pull in the upstream module's package + systemd.user unit definition.
    services.protonmail-bridge = {
      enable = true;
      logLevel = "info";
    };

    # Upstream binds to `graphical-session.target` — meaningless on a
    # server with no graphical session at boot. Force it onto the user
    # manager's default boot target. Also order after gnome-keyring so
    # Bridge sees an unlocked secret-service when it asks for vault key.
    systemd.user.services.protonmail-bridge.wantedBy = lib.mkForce [ "default.target" ];
    systemd.user.services.protonmail-bridge.after = lib.mkForce [ "network-online.target" "gnome-keyring.service" ];
    systemd.user.services.protonmail-bridge.wants = [ "network-online.target" "gnome-keyring.service" ];

    # ─── Headless gnome-keyring-daemon ─────────────────────────────────────
    # Bridge's vault is encrypted with a key stored in the Secret Service
    # (org.freedesktop.secrets via dbus). On a graphical Linux desktop this
    # is supplied by kwalletd / gnome-keyring spawned at login. On a
    # headless server, we run gnome-keyring ourselves as a user service,
    # unlocking it with a passphrase fed from sops via stdin.
    #
    # --components=secrets skips ssh/pkcs11 (we don't need them).
    # --unlock reads the password from stdin (one line, then EOF).
    systemd.user.services.gnome-keyring = {
      description = "GNOME keyring daemon (headless, secrets-only)";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type          = "simple";
        ExecStart     = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --foreground --components=secrets --unlock";
        StandardInput = "file:${config.sops.secrets.gnome_keyring_password.path}";
        Restart       = "on-failure";
        RestartSec    = "5s";
      };
    };

    # sops scalar: gnome_keyring_password (already encrypted in main.yaml).
    # mode 0400 + owner=alex so the systemd-user manager (running as alex)
    # can read it during ExecStart.
    sops.secrets.gnome_keyring_password = {
      owner = cfg.user;
      mode  = "0400";
    };

    # Enable user-linger so ${cfg.user}'s systemd-user manager starts at
    # boot. Without this, the user manager only runs once they actively
    # log in (SSH or KDE session), which defeats "headless at boot".
    # tmpfiles is the declarative path — equivalent to `loginctl enable-linger`.
    systemd.tmpfiles.rules = [
      "f /var/lib/systemd/linger/${cfg.user} 0644 root root - -"
    ];
  };
}

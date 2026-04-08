Deploy a new NixOS service into the homelab infrastructure. The service to deploy is: $ARGUMENTS

If no service name was provided in $ARGUMENTS, ask the user what service they want to deploy before proceeding.

Follow these steps in order. Do not skip steps. Do not proceed past an approval gate until the user explicitly approves.

---

## Step 1: Research

1. Confirm the service name.
2. Determine the correct deployment location by asking yourself if this is server-specific, workstation-specific, or usable by any host:
   - `hosts/common/optional/roles/server/` — server-specific
   - `hosts/common/optional/roles/workstation/` — workstation-specific
   - `hosts/common/optional/` — any host type
   - If unclear, ask the user.
3. Fetch the NixOS module options from `https://search.nixos.org/options?channel=25.11&query=<service>` and identify all required settings.
4. Determine whether the service needs:
   - **Secrets/credentials** → plan SOPS secret keys and `sops.secrets` declarations
   - **Persistent state** → plan impermanence directories; must use attrset form: `{ directory = "..."; user = "..."; group = "..."; }`
   - **Custom ports** → plan firewall rules (`networking.firewall.allowedTCPPorts`)
   - **Subdomain** → decide on a subdomain for Traefik and Blocky

---

## Step 2: Draft Config — ⛔ APPROVAL GATE

Draft the complete `<service>.nix` configuration using `templates/service.nix` as the base. The config must:

- Use `lib.mkEnableOption` and wrap everything in `lib.mkIf config.<service>.enable`
- Configure the service to be network-accessible over LAN, Tailscale, and via Traefik (set `HTTP_PORT`, bind to `0.0.0.0`)
- Never hardcode IPs — reference `config.lab.hosts.<name>.ip` if a host IP is needed
- Include `networking.firewall.allowedTCPPorts` for the service port
- Include persistence directories in attrset form with correct user/group if needed
- Include `sops.secrets` declarations if secrets are needed

**Present the full planned configuration (service.nix content, plus planned changes to dynamic-config.nix, blocky.nix, and homepage-dashboard.nix) to the user. Wait for explicit approval before writing any files.**

---

## Step 3: Write the Service File

After approval:

1. Write `<service>.nix` to the chosen directory.
2. Add the filename to the `imports` list in that directory's `default.nix`.

---

## Step 4: Enable on Host

If the target host was not specified, ask the user now. Add to `hosts/<host>/configuration.nix`:

```nix
<service>.enable = true;
```

---

## Step 5: Traefik Reverse Proxy

Add entries to `hosts/common/optional/roles/server/traefik/dynamic-config.nix`:

- A **router** entry for the service's subdomain (e.g., `<service>.${domain}`)
- A **service** entry pointing to `http://localhost:<port>`

Follow the exact structure of existing entries in that file.

---

## Step 6: DNS Entry

Add a custom DNS mapping for the service's subdomain in `hosts/common/optional/roles/server/blocky.nix`. Follow the exact pattern of existing entries.

---

## Step 7: Homepage Dashboard — ⛔ APPROVAL GATE

Read `hosts/common/optional/roles/server/homepage-dashboard.nix` and determine which existing section best fits the new service. Present your reasoning to the user and wait for approval before writing. Then add the entry following the existing format.

---

## Step 8: Secrets / SOPS (skip if service needs no secrets)

If the service requires credentials:

1. Inform the user they need to run `sops hosts/<host>/secrets.yaml` and add the raw secret values manually (Claude cannot decrypt or write plaintext secrets).
2. Add `sops.secrets.<key>` declarations in `<service>.nix` with the correct `owner` set to the service's runtime user.
3. Reference secrets in the config via `config.sops.secrets.<key>.path`.
4. If a `sops.templates` interpolation is needed (e.g., for a config file), add that too following the pattern in existing services.

---

## Step 9: Verify

Remind the user to:

1. Run `colmena apply` (or the appropriate deploy command) to push the config to the target host.
2. Check service logs after first deploy: `journalctl -u <service> -f` — a crash loop with "directory does not exist" means a missing subdirectory under the persistence path; fix with `systemd.tmpfiles.rules`.
3. Confirm the service is reachable via its Traefik subdomain in a browser.

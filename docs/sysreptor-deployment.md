# SysReptor — deployment notes

Self-hosted SysReptor Community (pentest reporting) on `saruman`, published through
Traefik on `atreides` at `sysreptor.<homelab_domain>`.

Sources for the facts below: the upstream docs (linked inline) and the module in this
repo, `hosts/common/optional/roles/server/sysreptor.nix`. Anything not verified against
those two is marked **unverified**.

## Components

An upstream SysReptor install is three containers — app, Postgres, Redis. There is **no
search tier** (Postgres does search natively) and **no Helm chart**; the supported
self-hosted path is Docker Compose, and we deliberately do not use their `install.sh` /
`update.sh` because they rewrite files in place. Instead the stack is declared in Nix and
run by podman, the same shape as `firecrawl.nix`.

| Container | Image | Published | Notes |
|---|---|---|---|
| `sysreptor-app` | `syslifters/sysreptor` | `8095:8000` on the host | Django/gunicorn + taskiq worker + headless Chromium for PDF rendering, all in one image |
| `sysreptor-db` | `postgres:14-alpine` | not published | Private network only |
| `sysreptor-redis` | `redis:8.0-alpine` | not published | Private network only, password required |

All three join the podman network `sysreptor` and reach each other by the aliases `db`,
`redis` and `app`.

## Ports and exposure

`8095` on the host, and **not** `8000` — `:8000` is speaches (Whisper STT) on saruman.
`8080` is Open WebUI. `8095` was verified free before the module was written.

The app port is not open to the LAN. Podman publishes ports via DNAT in the nat
`PREROUTING` chain, so traffic never reaches `nixos-fw` and `allowedTCPPorts` cannot
restrict it; the module therefore installs a raw-table rule that drops anything to `:8095`
whose source is not `atreides`:

```
iptables -t raw -I PREROUTING -p tcp --dport 8095 -m addrtype --dst-type LOCAL ! -s <atreides> -j DROP
```

This is the same mechanism `firecrawl.nix` uses for `:3002`. `dst-type LOCAL` leaves
container-to-container traffic on the bridge alone.

## Secrets

SysReptor reads its configuration from environment variables. The module renders one file,
`/run/secrets/rendered/sysreptor.env`, from sops, and every container consumes it via
`environmentFiles`.

Keys required in `hosts/saruman/secrets.yaml`:

| Key | Purpose |
|---|---|
| `sysreptor_secret_key` | Django `SECRET_KEY`. Upstream defaults to a hardcoded `TODO-change-me-…` value — overriding it is mandatory. |
| `sysreptor_encryption_keys` | AES-GCM encryption of data at rest. **Losing this makes the database and file backups unrecoverable.** |
| `sysreptor_db_password` | Postgres password |
| `sysreptor_redis_password` | Redis password |

> **These must exist before the deploy that enables the module.** A `sops.secrets.<name>`
> referenced by a module but absent from `main.yaml` fails activation, and `auto-deploy`
> then rolls the host back — the feature silently never appears.

Adding them requires `sops` and the age key, which exist only on `saruman`
(`/persist/var/lib/sops-nix/key.txt`, root-readable). Hermes has neither.

## Ingress

Traefik on `atreides` terminates TLS for the `*.home.<domain>` wildcard (Cloudflare
DNS-01) and proxies by hostname:

```
router  sysreptor  Host(`sysreptor.<homelab_domain>`)  →  service sysreptor
service sysreptor  →  http://10.1.8.6:8095
```

`<homelab_domain>` has **no public DNS record** — it resolves only through Blocky
split-DNS, so off-LAN clients need tailnet plus split DNS plus an accepted subnet route.

The app trusts the proxy through `USE_X_FORWARDED_HOST`, `USE_X_FORWARDED_PORT`,
`SECURE_SSL_REDIRECT` and `SECURE_PROXY_SSL_HEADER=HTTP_X_FORWARDED_PROTO,https`, and
`ALLOWED_HOSTS` lists the FQDN, `localhost`, `127.0.0.1` and saruman's LAN IP. Django
derives `CSRF_TRUSTED_ORIGINS` and `MFA_FIDO2_RP_ID` from `ALLOWED_HOSTS` when a single
host is configured — worth re-checking if the hostname ever changes.

Split DNS costs nothing functionally: SysReptor bundles its frontend assets, PDF.js and
Excalidraw inside the image, and Chromium renders PDFs against loopback. Only links inside
generated reports point at a name that resolves on the LAN/tailnet alone.

## Persistence

State lives outside the container so it survives the impermanent root:

```
/persist/var/lib/sysreptor/db      0700  uid 70   (postgres)
/persist/var/lib/sysreptor/redis   0700  uid 999  (redis)
/persist/var/lib/sysreptor/data    0700  uid 1000 (app: uploaded files, rendered PDFs)
```

Created by `systemd.tmpfiles.rules`; impermanence bind-mounts the parent but does not
create subdirectories, so the rules are load-bearing.

## First run

Nothing creates a login. After the first successful start, create the initial superuser:

```
podman exec -it sysreptor-app python3 manage.py createsuperuser
```

Community edition has no role system: up to 3 users, all superusers with access to every
project. Pro (€/$ per user per month, billed annually) adds roles, comments, version
history, concurrent editing, SSO, audit logs and spell check.

## Backup and restore

`manage.py backup` emits a **single archive containing both the database export and every
file under `/data`** — that is the whole state. Redis is ephemeral and is not backed up,
and there is no search index to rebuild.

```
podman exec sysreptor-app python3 manage.py backup \
  > /mnt/nas-backups/sysreptor/sysreptor-$(date -I).zip
```

Restore, on the **same SysReptor version**, into empty volumes:

```
cat backup.zip | podman exec -i sysreptor-app python3 manage.py restorebackup
```

Backing up the archive is not sufficient on its own: without `sysreptor_encryption_keys`
the contents cannot be decrypted, so that secret has to be preserved separately from the
database — it lives in the sops file, which is in git.

## Upgrades

- App and plugin migrations run automatically on container start.
- Releases are `YYYY.NN`. Bumping the app image is normally low risk.
- The **Postgres major version is the sharp edge.** Upstream moved from 14 to 18 via a
  dedicated upgrade path; a silent major bump against an existing data directory will
  fail or corrupt it. Pin both the app tag and `postgres:14-alpine` and treat a Postgres
  major upgrade as a planned migration, not an image bump.

## Verification checklist (after approval and deploy)

1. `systemctl --failed` on `saruman` is empty; `podman-sysreptor-{app,db,redis}` active.
2. `curl -sI http://10.1.8.6:8095/` from **atreides** answers; the same request from
   another host times out (proves the raw-table drop rule).
3. `https://sysreptor.<homelab_domain>` serves the login page with a valid cert.
4. `/run/secrets/rendered/sysreptor.env` exists, mode 0400.
5. `manage.py backup` writes a non-empty archive to the NAS dataset.
6. Homepage dashboard shows the SysReptor tile and it links through.

## Open items

- **The app image is pinned to `latest`.** `firecrawl.nix` sets the house standard — digest
  pinning with a comment recording when and why. SysReptor should be pinned the same way
  before this is relied on, so an unattended `podman pull` cannot change the running
  version under a live project.
- **Outbound telemetry.** SysReptor fetches release notifications from
  `sysreptor.com` and, on Pro, POSTs licence telemetry daily. Community installs on a
  private network will log errors if `saruman` has no outbound route to it — harmless, but
  it will appear in the journal.
- **`unifi`, `ilo`, `prdcoffeeubuntu`** and other unrelated cleanups are out of scope here.

# SysReptor — deployment notes

Self-hosted SysReptor Community (pentest reporting) on `saruman`, published through
Traefik on `atreides` at `sysreptor.<homelab_domain>`.

Sources for the facts below: upstream's own compose file, `app.env.example`,
`api/src/sysreptor/conf/settings.py` and `api/start.sh` (linked inline), plus the module in
this repo, `hosts/common/optional/roles/server/sysreptor.nix`. Anything not verified against
those is marked **unverified**.

## Components

An upstream SysReptor install is three containers — app, Postgres, Redis. There is **no
search tier** (Postgres does search natively) and **no Helm chart**; the supported
self-hosted path is Docker Compose, and we deliberately do not use their `install.sh` /
`update.sh` because they rewrite files in place. Instead the stack is declared in Nix and
run by podman, the same shape as `firecrawl.nix`.

| Container | Image (pinned by digest) | Published | Notes |
|---|---|---|---|
| `sysreptor-app` | `syslifters/sysreptor` @ `bddb1b6e1e58` | `8095:8000` on the host | App `VERSION=2026.102`. Django/gunicorn + taskiq worker + headless Chromium for PDF rendering, one image |
| `sysreptor-db` | `postgres` @ `e7d9e6aac7fe` | not published | `14-alpine`, upstream's own compose default |
| `sysreptor-redis` | `redis` @ `5f61955be8ab` | not published | `8.0-alpine`, `--requirepass` |

All three join the podman network `sysreptor` and reach each other by the aliases `db`,
`redis` and `app`. Pinned 2026-11-17 by digest, not tag — an unattended `podman pull` must
not change the running version under a live project.

`api/start.sh` with no arguments runs **migrate, then the server and the taskiq worker**, so
the image's default CMD is correct and no custom command is needed. The app container runs
with `--init`, as upstream does, since one container supervises three processes.

### Gotcha: the two containers want different database variable names

Verified in `conf/settings.py`:

- the **db** container reads `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- the **app** container reads `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`,
  `DATABASE_USER`, `DATABASE_PASSWORD`

`DATABASE_HOST` defaults to the **empty string**, so an app configured with only the
`POSTGRES_*` names — the obvious mistake, and the one this module originally made — cannot
reach the database at all and fails at startup. Both sets are rendered into the single
`sysreptor.env`; each container ignores the other's.

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

Same mechanism `firecrawl.nix` uses for `:3002`. `dst-type LOCAL` leaves
container-to-container traffic on the bridge alone.

## Secrets

SysReptor reads its configuration from environment variables. The module renders one file,
`/run/secrets/rendered/sysreptor.env`, from sops, and every container consumes it via
`environmentFiles`.

Keys required in `hosts/saruman/secrets.yaml`:

| Key | Purpose |
|---|---|
| `sysreptor_secret_key` | Django `SECRET_KEY`. Upstream defaults to a hardcoded `TODO-change-me-…` value — overriding it is mandatory. |
| `sysreptor_encryption_keys` | AES-GCM encryption at rest. **Losing this makes the database and file backups unrecoverable.** Must be the whole JSON array, not a bare string — `settings.py` casts it with `EncryptionKey.from_json_list`. |
| `sysreptor_db_password` | Postgres password (used by both `POSTGRES_PASSWORD` and `DATABASE_PASSWORD`) |
| `sysreptor_redis_password` | Redis password |

`sysreptor_encryption_keys` has to look like this, with the `id` matching
`DEFAULT_ENCRYPTION_KEY_ID` (the module sets `primary`):

```
[{"id":"primary","key":"<32-byte base64>","cipher":"AES-GCM","revoked":false}]
```

> **These must exist before the deploy that enables the module.** A `sops.secrets.<name>`
> referenced by a module but absent from the file fails activation, and `auto-deploy` then
> rolls the host back — the feature silently never appears.

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

Blocky resolves that domain from an **explicit per-service mapping**
(`hosts/common/optional/roles/server/blocky.nix`), not a wildcard, so a new Traefik router is
unreachable until its name is added there too. This was missed on the first deploy: the
containers came up healthy and answered `200` from atreides with the right Host header, but
the name did not resolve at all — which looks exactly like a failed deployment. **Adding a
service is two files, not one.**

The app trusts the proxy through `USE_X_FORWARDED_HOST`, `USE_X_FORWARDED_PORT` and
`SECURE_SSL_REDIRECT`. `SECURE_PROXY_SSL_HEADER` is **hardcoded** in `settings.py`, not an
env var, so it is not set. `ALLOWED_HOSTS` carries the single FQDN; Django appends
`localhost`/`127.0.0.1`/`[::1]` itself and derives `CSRF_TRUSTED_ORIGINS` and
`MFA_FIDO2_RP_ID` from a single-host value — worth re-checking if the hostname changes.

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

The Postgres volume mounts at **`/data`** with `PGDATA=/data`, matching upstream. The
alpine image's own default is `/var/lib/postgresql/data`; mounting there instead would
leave the container initialising a *second* datadir the moment anything changed.

## What's the deal with Postgres

Three separate things, all of which bite differently:

1. **It is not shared.** SysReptor runs its own Postgres in its own container on the private
   network, nothing published. Paperless-ngx's Postgres on `saruman` listens on
   `127.0.0.1:5432` on the host and is completely separate — no port clash, no shared
   instance, no version coupling between the two services.
2. **The data directory is version-specific.** Postgres refuses to start against a datadir
   written by a different *major* version. Upstream's compose pins the version through
   `SYSREPTOR_POSTGRES_VERSION`, defaulting to `14`, and has since moved to `18` — with a
   dedicated `upgrade_postgres.sh` / `pgautoupgrade` path for existing installs. So an
   unexamined bump of that image is a data-loss bug, not a version bump: the container
   either refuses to start or, worse, comes up against an empty new datadir while the real
   one sits beside it unread. This module therefore pins the db image to `14-alpine` by
   digest and treats a major upgrade as a **planned migration** — dump, `pg_upgrade` (or
   the upstream script), verify — never as an image tag change.
3. **`manage.py migrate` runs on every boot.** `api/start.sh` defaults to migrate-then-serve,
   so schema changes for the pinned app version apply automatically. That is safe for
   same-version restarts, but it does mean the app's schema and the app version move
   together — another reason the app and db images get bumped as a pair, deliberately.

## First run

Nothing creates a login. After the first successful start, create the initial superuser:

```
podman exec -it sysreptor-app python3 manage.py createsuperuser
```

Community edition has no role system: up to 3 users, all superusers with access to every
project. Pro (per user per month, billed annually) adds roles, comments, version history,
concurrent editing, SSO, audit logs and spell check.

## Backup and restore

> **`manage.py backup` is a Pro feature.** Verified against the running container:
> `podman exec sysreptor-app python3 manage.py backup` exits 1 with
> `CommandError: Professional license required`. The community procedure is a plain
> `pg_dump` plus a tar of `/data`; between them they are the whole state. Redis is
> ephemeral and is not backed up, and there is no search index to rebuild.

Community backup, both halves into the same dated directory:

```
D=/mnt/nas-backups/sysreptor/$(date -I); mkdir -p "$D"
podman exec sysreptor-db pg_dump -U sysreptor sysreptor | gzip > "$D/db.sql.gz"
podman exec sysreptor-app tar -C / -cf - data | gzip > "$D/data.tar.gz"
```

Restore, on the **same SysReptor version**, into empty volumes, with the app stopped:

```
gunzip -c "$D/db.sql.gz" | podman exec -i sysreptor-db psql -U sysreptor -d sysreptor
gunzip -c "$D/data.tar.gz" | podman exec -i sysreptor-app tar -C / -xzf -
```

Neither half is sufficient on its own: without `sysreptor_encryption_keys` the contents
cannot be decrypted, so that secret must be preserved separately from the database — it
lives in the sops file, which is in git.

## Smoke tests

The app image ships a health endpoint used by upstream's own compose healthcheck:
`/api/public/utils/healthcheck/`.

**Before deployment** — the gate, run from `hermes`/`saruman`, none of it touching the host:

| Check | Command | Expected |
|---|---|---|
| Both toplevels evaluate | `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` on saruman, for `saruman` and `atreides` | a `/nix/store/…-nixos-system-<host>.drv` path |
| App port free | `ss -lntu \| grep :8095` on saruman | no output |
| Images resolvable | registry `HEAD /v2/<repo>/manifests/<digest>` against Docker Hub | HTTP 200 for all three |
| Env names correct | compare the module against `conf/settings.py` and `deploy/sysreptor/docker-compose.yml` | `DATABASE_*`, not `POSTGRES_*`, on the app |
| Secrets present | `grep '^sysreptor_' hosts/saruman/secrets.yaml` | all four keys |

**After deployment** — run in this order, because each proves a different layer:

1. `systemctl --failed` on saruman is empty; `podman-sysreptor-{app,db,redis}` all active,
   and `podman ps` shows no restart loop.
2. `podman exec sysreptor-db pg_isready -U sysreptor` → `accepting connections` (proves the
   db came up on the right datadir).
3. From **atreides**, `curl -sf http://10.1.8.6:8095/api/public/utils/healthcheck/` succeeds.
   From any *other* host the same request must hang or be refused — that is the drop rule
   working, and it is the check that distinguishes "bound" from "reachable".
4. `https://sysreptor.<homelab_domain>` serves the login page with a valid certificate, from
   a LAN client.
5. `/run/secrets/rendered/sysreptor.env` exists, owned by root, mode 0400.
6. The Community backup path works: `pg_dump -U sysreptor sysreptor | gzip` returns a
   non-empty dump (72 tables at first boot) and a tar of `/data` succeeds — see the
   Pro-only note above, `manage.py backup` is not available here.
7. Homepage dashboard shows the SysReptor tile and links through.

## Open items

- **Outbound telemetry.** SysReptor fetches release notifications from `sysreptor.com` and,
  on Pro, POSTs licence telemetry daily. A Community install with no outbound route to it
  logs errors — harmless, but visible in the journal.
- **No healthcheck in the Nix module.** `virtualisation.oci-containers` has no healthcheck
  option, so podman does not gate dependents on the app's health endpoint as upstream's
  compose does with `condition: service_healthy`. Startup ordering relies on
  `start.sh` retrying the DB connection.
- **`unifi`, `ilo`** and other unrelated cleanups are out of scope here.
  (`prdcoffeeubuntu` was cleaned out of `hosts-data.nix` and `blocky.nix` on 2026-11-17.)

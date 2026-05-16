# platform-infra

Local dev infrastructure for the Odoo Entitlements SaaS Platform.
Brings up the three backing services every application service needs to
talk to: PostgreSQL 18, Valkey 8, Keycloak 26 (with two pre-imported
realms).

This repo is intentionally narrow: it is the substrate, not the
application. Coolify project definitions, staging/prod overlays, and
secrets manifests will be added later — see the "What's NOT here yet"
section at the bottom.

---

## Prerequisites

- Docker Engine 24+ with Compose v2 (Docker Desktop on Windows works
  through the WSL backend; `docker --version` should print 24.x or
  newer).
- GNU Make (already on most WSL distros).
- Free TCP ports `5432`, `6379`, `8080` on the host. If any are taken,
  edit `.env` to remap.

## Quick start

```bash
cp .env.example .env
make up
make check   # verifies all three services are responding
```

First start takes ~60 seconds because Keycloak imports both realms and
runs its own DB migrations against the `keycloak` Postgres database.
Subsequent `make up` is a few seconds.

## What's running

| Service  | Image                            | Host port | Purpose                                                         |
|----------|----------------------------------|-----------|-----------------------------------------------------------------|
| postgres | `postgres:18-alpine`             | `5432`    | `platform` DB (5 schemas per HLD §7.2) + `keycloak` DB          |
| valkey   | `valkey/valkey:8-alpine`         | `6379`    | Taskiq broker + Valkey Streams for domain events (HLD §11)      |
| keycloak | `quay.io/keycloak/keycloak:26.0` | `8080`    | OIDC IdP with `customers` and `operators` realms                |

All three sit on the `platform-net` Docker network. Application
services (running on the host or in their own containers) reach them
via `localhost:<port>` from the host, or by hostname (`postgres`,
`valkey`, `keycloak`) if they join the same network.

## Default credentials (DEV ONLY)

Treat all of these as throwaway. They are baked into `.env.example` and
the realm exports purely so a fresh `make up` is immediately usable.

**Postgres**
- User: `platform`
- Password: `platform_dev_password`
- Databases: `platform`, `keycloak`

**Keycloak — master realm (admin console only)**
- URL: <http://localhost:8080/admin/>
- User: `admin`
- Password: `admin`

**Keycloak — `customers` realm**
- Test user: `test-customer@example.com` / `testpass`
- OIDC discovery: <http://localhost:8080/realms/customers/.well-known/openid-configuration>

**Keycloak — `operators` realm**
- Test admin: `test-admin@example.com` / `AdminTest123`
- Test sales: `test-sales@example.com` / `SalesTest123`
- Test support: `test-support@example.com` / `SupportTest123`
- OIDC discovery: <http://localhost:8080/realms/operators/.well-known/openid-configuration>

## Daily commands

```bash
make up         # start everything
make ps         # see status
make logs       # tail logs (Ctrl-C to exit)
make down       # stop (data preserved)
make check      # smoke-test all three services
make psql       # psql shell on the platform DB
make psql-kc    # psql shell on the keycloak DB
make valkey-cli # valkey-cli shell
make help       # all targets with one-liners
```

## Verifying each piece works

The HLD specifies a done-state for this repo: `docker compose up`, you
can `psql` into the database, hit `http://localhost:8080` for the
Keycloak admin console, and `valkey-cli ping` returns PONG. To check
each manually:

```bash
# Postgres — should print all 5 schemas
make psql -- -c "\\dn catalog|subscription|billing|provisioning|telemetry"

# Valkey
make valkey-cli ping

# Keycloak realm discovery
curl -s http://localhost:8080/realms/customers/.well-known/openid-configuration | jq .issuer
curl -s http://localhost:8080/realms/operators/.well-known/openid-configuration | jq .issuer
```

`make check` runs the equivalent of all three in one shot.

## What the Postgres init does

`postgres/init/01-init.sql` runs **only on first container start** (when
the data volume is empty). It does two things:

1. Creates the five logical-module schemas inside the `platform`
   database: `catalog`, `subscription`, `billing`, `provisioning`,
   `telemetry`. Each service's Alembic migrations will create tables
   inside its own schema later — see HLD §7.2.
2. Creates a separate `keycloak` database (same cluster, same user,
   isolated tables) for the Keycloak container's storage.

If you change the init script, you must run `make reset` to apply it —
the script does not re-run on a populated volume.

## Editing realms

Two realm export JSONs live in `keycloak/realms/`. On every fresh start
they are imported into Keycloak via the `--import-realm` flag. The
import is idempotent: if a realm with the same name already exists in
the `keycloak` database, the import is skipped (this is why edits made
through the admin UI persist across restarts, but only as long as the
DB volume sticks around).

To make a permanent change:

1. Edit in the admin UI: <http://localhost:8080/admin/>.
2. `make keycloak-export-customers` or `make keycloak-export-operators`
   to dump the live realm to `keycloak/realms/<realm>-exported.json`.
3. Diff, review, and copy over the committed file.
4. Commit.

Caveat: Keycloak's own export does **not** include user passwords. The
test users in our committed realm files have hard-coded passwords in
their `credentials` blocks so that `make reset` always yields a usable
stack. If you re-export, restore the `credentials` blocks by hand or
delete the test users from the export.

To completely reset Keycloak's state and re-run the import:

```bash
make reset   # destructive — drops all data volumes, you'll be prompted
```

## Networking notes

- The compose file binds each service to all interfaces by default
  (`5432:5432`, etc.). If you prefer localhost-only, change to
  `127.0.0.1:5432:5432` in `docker-compose.yml`.
- Application services running on the **host** (your WSL shell)
  connect to `localhost:5432` etc.
- Application services running in **their own containers** that join
  the `platform-net` network connect by hostname: `postgres:5432`,
  `valkey:6379`, `keycloak:8080`. This is the path the
  `platform-api` Coolify deployment will eventually take.

## What's NOT here yet

Per the build plan, this repo will accumulate the following only when
they're needed:

- Coolify project definitions for `dev`, `staging`, `prod`.
- Per-environment overlay files for the application services.
- Encrypted secrets manifests for `staging` / `prod`.
- A `docker-compose.override.yml` for running the application services
  themselves alongside this infra during local dev (likely once
  `platform-api` is the second repo we stand up).
- TLS certs and reverse-proxy config for staging/prod Keycloak.

If you reach for something that should be here but isn't, file it as a
TODO at the top of this README so it's not forgotten.

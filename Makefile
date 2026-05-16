# platform-infra / Makefile
# =========================
# Convenience wrappers around `docker compose`. Run `make help` to list
# targets. All targets assume you have copied .env.example -> .env.

SHELL := /bin/bash
COMPOSE := docker compose

# Load .env so $${POSTGRES_USER} etc. are visible to the host shell for
# commands like `psql` below. Falls back silently if .env is missing.
ifneq (,$(wildcard ./.env))
include .env
export
endif

.PHONY: help up down ps logs restart \
        psql psql-kc valkey-cli \
        reset nuke \
        keycloak-export-customers keycloak-export-operators \
        check

help:  ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ---------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------

up:  ## Start all services in the background.
	$(COMPOSE) up -d
	@echo
	@echo "Bringing services up. Watch with:  make logs"
	@echo "Quick check:                       make check"

down:  ## Stop all services (data preserved).
	$(COMPOSE) down

restart:  ## Restart all services.
	$(COMPOSE) restart

ps:  ## Show service status.
	$(COMPOSE) ps

logs:  ## Tail logs from all services. Ctrl-C to exit.
	$(COMPOSE) logs -f

# ---------------------------------------------------------------------
# Interactive shells
# ---------------------------------------------------------------------

psql:  ## Open a psql shell on the `platform` database.
	$(COMPOSE) exec postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

psql-kc:  ## Open a psql shell on the `keycloak` database.
	$(COMPOSE) exec postgres psql -U $(POSTGRES_USER) -d keycloak

valkey-cli:  ## Open valkey-cli against the local Valkey.
	$(COMPOSE) exec valkey valkey-cli

# ---------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------

check:  ## Verify each service is reachable and behaving.
	@echo "--- postgres ----------------------------------------------"
	@$(COMPOSE) exec -T postgres pg_isready -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		&& echo "  schemas:" \
		&& $(COMPOSE) exec -T postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) \
		    -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('catalog','subscription','billing','provisioning','telemetry') ORDER BY schema_name;"
	@echo
	@echo "--- valkey ------------------------------------------------"
	@$(COMPOSE) exec -T valkey valkey-cli ping
	@echo
	@echo "--- keycloak ----------------------------------------------"
	@echo "Admin console: http://localhost:$${KEYCLOAK_HOST_PORT:-8080}/admin/"
	@echo "Realms imported:  customers, operators"
	@curl -fsS "http://localhost:$${KEYCLOAK_HOST_PORT:-8080}/realms/customers/.well-known/openid-configuration" >/dev/null \
		&& echo "  customers realm OIDC discovery OK" \
		|| echo "  customers realm NOT ready yet (it can take 30-60s on first start)"
	@curl -fsS "http://localhost:$${KEYCLOAK_HOST_PORT:-8080}/realms/operators/.well-known/openid-configuration" >/dev/null \
		&& echo "  operators realm OIDC discovery OK" \
		|| echo "  operators realm NOT ready yet (it can take 30-60s on first start)"

# ---------------------------------------------------------------------
# Reset / destroy
# ---------------------------------------------------------------------

reset:  ## DESTRUCTIVE: drop volumes and rebuild from init scripts + realm exports.
	@echo "This will delete all local Postgres + Valkey data and the keycloak DB."
	@read -p "Type 'reset' to confirm: " ans && [ "$$ans" = "reset" ]
	$(COMPOSE) down -v
	$(COMPOSE) up -d

nuke:  ## Same as reset but skips the confirmation prompt. Use carefully.
	$(COMPOSE) down -v
	$(COMPOSE) up -d

# ---------------------------------------------------------------------
# Keycloak realm round-trip
# ---------------------------------------------------------------------
# Workflow: edit a realm in the admin UI -> export to file -> commit.
# The export writes one file per realm to keycloak/export-tmp/, then we
# move it over the canonical realm export.
#
# Caveat: Keycloak's export does NOT include user passwords. The test
# users with hard-coded passwords in our committed realm files exist
# purely so a fresh `make up` is usable; if you re-export, restore the
# `credentials` block by hand or recreate the test users post-import.

keycloak-export-customers:  ## Export the live customers realm to keycloak/realms/customers-realm.json.
	@mkdir -p keycloak/export-tmp
	$(COMPOSE) exec -T keycloak \
		/opt/keycloak/bin/kc.sh export \
		--realm customers \
		--users realm_file \
		--file /opt/keycloak/data/import/customers-realm.exported.json
	@echo "Exported. Review the diff before overwriting the committed file:"
	@echo "  diff keycloak/realms/customers-realm.json keycloak/realms/customers-realm.exported.json"

keycloak-export-operators:  ## Export the live operators realm to keycloak/realms/operators-realm.json.
	@mkdir -p keycloak/export-tmp
	$(COMPOSE) exec -T keycloak \
		/opt/keycloak/bin/kc.sh export \
		--realm operators \
		--users realm_file \
		--file /opt/keycloak/data/import/operators-realm.exported.json
	@echo "Exported. Review the diff before overwriting the committed file:"
	@echo "  diff keycloak/realms/operators-realm.json keycloak/realms/operators-realm.exported.json"

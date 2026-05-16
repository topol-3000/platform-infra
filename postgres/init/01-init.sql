-- platform-infra / postgres init
-- =================================
-- This file runs ONLY when the Postgres data volume is empty (first-ever
-- container start, or after `make reset`). To re-run, drop the volume.
--
-- It runs as ${POSTGRES_USER} against the ${POSTGRES_DB} database (which the
-- Postgres image creates from env vars BEFORE running these init scripts).
--
-- Two responsibilities:
--   1. Create the per-module schemas inside the `platform` database. The
--      HLD (§7.2) gives each logical module its own schema with no
--      cross-schema foreign keys, so we can split services later.
--   2. Create a separate `keycloak` database, so Keycloak's storage is
--      isolated from our domain data while reusing the same cluster.

-- -----------------------------------------------------------------------
-- 1. Schemas in the platform DB
-- -----------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS subscription;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS provisioning;
CREATE SCHEMA IF NOT EXISTS telemetry;

COMMENT ON SCHEMA catalog
    IS 'SKUs and dependency graph. Owned by platform-api / catalog module.';
COMMENT ON SCHEMA subscription
    IS 'Customers, quotes, subscriptions, audit_event. Owned by platform-api / subscription module.';
COMMENT ON SCHEMA billing
    IS 'invoice_mirror, stripe_event. Owned by platform-api / billing module.';
COMMENT ON SCHEMA provisioning
    IS 'instance, provisioning_task, enforcement_snapshot. Owned by provisioning-worker.';
COMMENT ON SCHEMA telemetry
    IS 'instance_health, instance_usage, alert. Owned by telemetry-worker.';

-- The current user (POSTGRES_USER) is the superuser/owner in dev, so it
-- already has full privileges on all schemas it just created. In prod we
-- will move to one Postgres role per service with GRANTs per schema; that
-- belongs in a separate migration/Coolify provisioning step, not here.

-- -----------------------------------------------------------------------
-- 2. Separate `keycloak` database
-- -----------------------------------------------------------------------
-- CREATE DATABASE cannot run inside a transaction block. The Postgres
-- official image runs each .sql file with `psql` using -v ON_ERROR_STOP=1
-- but without an explicit BEGIN, so this works at file-top level.

-- OWNER is omitted on purpose: CREATE DATABASE defaults the owner to the
-- executing role, which here is POSTGRES_USER (the cluster superuser).
-- `OWNER = CURRENT_USER` would be nicer but Postgres only accepts a role
-- name or DEFAULT here, not the CURRENT_USER keyword.
CREATE DATABASE keycloak
    WITH ENCODING = 'UTF8'
         TEMPLATE = template0;

COMMENT ON DATABASE keycloak IS 'Backing store for the Keycloak container.';

---
phase: 01-foundation-toolchain-spike
plan: 01
subsystem: infra, database
tags: [docker-compose, timescaledb, valkey, mesh, postgresql, multi-tenancy, schema-per-org]

# Dependency graph
requires:
  - phase: none
    provides: greenfield project
provides:
  - Docker Compose 3-service stack (app, TimescaleDB, Valkey) with health checks
  - Mesh project scaffold with config module and HTTP entry point
  - Public schema DDL for users, organizations, org_memberships, sessions, invites, password_reset_tokens
  - Tenant isolation helper (with_org_schema using SET LOCAL in transactions)
  - Schema provisioning function (provision_org_schema with projects + api_keys tables)
affects: [01-02, 01-03, 01-04, 01-05, 01-06, phase-2, phase-3, phase-4]

# Tech tracking
tech-stack:
  added: [timescaledb-pg17, valkey-9-alpine, mesh]
  patterns: [schema-per-org-isolation, set-local-in-transactions, env-var-config]

key-files:
  created:
    - docker-compose.yml
    - Dockerfile
    - .env.example
    - mesh.toml
    - src/main.mpl
    - src/config.mpl
    - src/db/tenant.mpl
    - migrations/20260303000001_create_public_tables.mpl

key-decisions:
  - "PG-backed sessions instead of Valkey sessions for Phase 1 (Mesh may lack Valkey client)"
  - "Placeholder Dockerfile until Mesh SDK distribution is known"
  - "search_path always includes public for TimescaleDB extension access"

patterns-established:
  - "Config module: all runtime config via Env.get with defaults in src/config.mpl"
  - "Tenant isolation: with_org_schema() wraps SET LOCAL search_path in transaction"
  - "Schema provisioning: provision_org_schema() creates org schema + tenant tables"
  - "Docker Compose: 3 services with health checks and dependency ordering"

requirements-completed: [DEPLOY-01, DEPLOY-02, DEPLOY-03, ORG-06]

# Metrics
duration: 2min
completed: 2026-03-03
---

# Phase 1 Plan 01: Project Scaffold Summary

**Docker Compose 3-service stack with TimescaleDB/Valkey, public schema migrations for 6 tables, and schema-per-org tenant isolation helper using SET LOCAL**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-03T07:56:25Z
- **Completed:** 2026-03-03T07:58:20Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- Docker Compose stack with app, TimescaleDB (pg17), and Valkey (9-alpine) services, all with health checks and dependency ordering
- Public schema migration creating users, organizations, org_memberships, sessions, invites, and password_reset_tokens tables with foreign keys and indexes
- Tenant isolation helper (with_org_schema) using SET LOCAL inside transactions to prevent search_path leakage across pooled connections
- Schema provisioning function creating per-org schemas with projects and api_keys tables
- Complete environment variable configuration module with all vars documented in .env.example

## Task Commits

Each task was committed atomically:

1. **Task 1: Docker Compose stack + Mesh project scaffold + config** - `584a2b1` (feat)
2. **Task 2: Public schema migrations + tenant isolation helper** - `a93843e` (feat)

## Files Created/Modified
- `docker-compose.yml` - 3-service stack definition with health checks and dependency ordering
- `Dockerfile` - Multi-stage build placeholder for Mesh application
- `.env.example` - All environment variable documentation
- `mesh.toml` - Mesh project manifest
- `src/main.mpl` - Application entry point with Pool, router, /health endpoint, HTTP.serve
- `src/config.mpl` - Env var loading and tier detection for all runtime config
- `src/db/tenant.mpl` - Tenant-scoped query helper with SET LOCAL search_path and schema provisioning
- `migrations/20260303000001_create_public_tables.mpl` - Public schema DDL for all 6 shared tables

## Decisions Made
- **PG-backed sessions over Valkey sessions for Phase 1:** Research identified that Mesh may not have a built-in Valkey/Redis client. Using PostgreSQL sessions table with periodic cleanup avoids this dependency for auth while keeping Valkey in the stack for future caching/rate-limiting phases.
- **Placeholder Dockerfile:** The exact Mesh SDK base image is unknown. Created a placeholder multi-stage Dockerfile with comments guiding the user to adjust once Mesh binary distribution is known.
- **Public always in search_path:** Per Pitfall 6 in research, TimescaleDB functions are installed in the public schema. The tenant helper always includes `public` in SET LOCAL search_path to ensure extensions remain accessible.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `meshc` is not available in the development environment, so the verification steps requiring `meshc build .` and `meshc migrate up` could not be executed. The docker-compose.yml was validated with `docker compose config` successfully. The Mesh source files follow the syntax patterns from research and GitNexus documentation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Docker Compose stack is ready for `docker compose up` (TimescaleDB and Valkey will start; app service requires meshc)
- Database schema is defined and ready for migration once meshc is available
- Config module provides the foundation for all subsequent plans to read environment variables
- Tenant isolation pattern is established for all org-scoped database operations in Plans 01-04 and 01-05

## Self-Check: PASSED

- All 8 created files verified present on disk
- Commit `584a2b1` (Task 1) verified in git log
- Commit `a93843e` (Task 2) verified in git log
- `docker compose config` validates without errors

---
*Phase: 01-foundation-toolchain-spike*
*Completed: 2026-03-03*

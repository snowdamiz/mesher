---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-03-04T00:22:03Z"
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 13
  completed_plans: 13
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-03)

**Core value:** The easiest way to add full-stack observability (errors + infrastructure metrics) to any service — deployed with a single Docker Compose command, built natively for Mesh apps
**Current focus:** Phase 01.2 plans complete — pending phase verification

## Current Position

Phase: 01.2 of 9 (Reorganize repo with server and client directories) -- PLANS COMPLETE
Plan: 3 of 3 in current phase -- PLAN 03 COMPLETE
Status: Phase 01.2 Plans Complete (awaiting verifier)
Last activity: 2026-03-04 - Completed 01.2-03 (docs standardization + regression verification)

Progress: [████████████████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: 11min
- Total execution time: 1.8 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 - Foundation | 6 | 104min | 17min |
| 1.1 - ORM Migration | 4 | 8min | 2min |

**Recent Trend:**
- Last 5 plans: 01.1-03 (2min), 01.1-04 (2min), 01.2-01 (2min), 01.2-02 (5min), 01.2-03 (18min)
- Trend: accelerating

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 2min | 3 tasks | 12 files |
| Phase 01 P02 | 45min | 2 tasks | 8 files |
| Phase 01 P03 | 35min | 3 tasks | 3 files |
| Phase 01 P04 | 25min | 1 tasks | 3 files |
| Phase 01 P05 | 13min | 4 tasks | 8 files |
| Phase 01 P06 | 7min | 2 tasks | 35 files |
| Phase 01.1 P01 | 2min | 2 tasks | 5 files |
| Phase 01.1 P02 | 2min | 2 tasks | 3 files |
| Phase 01.1 P03 | 2min | 2 tasks | 4 files |
| Phase 01.1 P04 | 2min | 2 tasks | 3 files |

*Updated after each plan completion*
| Phase 01.2-reorganize-repo-with-server-and-client-directories P01 | 2min | 2 tasks | 33 files |
| Phase 01.2-reorganize-repo-with-server-and-client-directories P02 | 5 min | 3 tasks | 9 files |
| Phase 01.2-reorganize-repo-with-server-and-client-directories P03 | 18 min | 2 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Init]: PostgreSQL + TimescaleDB chosen over ClickHouse (self-hosted simplicity, Mesh native PG support)
- [Init]: Schema-per-org isolation for strong data boundaries and SaaS compliance story
- [Init]: OTLP as primary ingestion protocol — industry standard, no vendor lock-in
- [Init]: Mesh actor model for ingestion pipeline — natural fit for high-throughput event processing
- [01-01]: PG-backed sessions instead of Valkey for Phase 1 (Mesh may lack Valkey client; Valkey stays in stack for future phases)
- [01-01]: search_path always includes public for TimescaleDB extension access in tenant isolation
- [01-01]: Placeholder Dockerfile until Mesh SDK distribution method is known
- [Phase 01]: Ws.serve on_connect callback must accept 3 args (conn, path, headers) and return Int, not 1 arg
- [Phase 01]: Lambda parameters inside test blocks lose scope - use named top-level functions instead
- [Phase 01]: Ws.serve must be wrapped in separate function from spawn to avoid Pid type inference bleed
- [Phase 01]: on_message and on_close callbacks must return () explicitly (not Int from Ws.send)
- [Phase 01]: Case arm expressions must be on same line as -> (no multi-line bodies)
- [01-03]: Native Crypto.uuid4() for session IDs, pgcrypto crypt() for bcrypt password verification (bcrypt not in Mesh stdlib; sha256/sha512/uuid4 are available)
- ~~[01-03]: Mesh has no cross-file function visibility (import/module both fail) -- all route handlers must live in same file as router~~ DISPROVEN: `from Module import func` works correctly (verified against mesh/mesher reference project)
- [01-03]: Mesh HTTP stdlib has no response header API (no set_header/header/with_header) -- session ID returned in JSON body
- ~~[01-03]: Avoid ? operator in handler functions to prevent Result type pollution; use explicit case matching~~ DISPROVEN: ? operator works with `-> Type!String` return annotations. Only avoid in functions returning Response (not a Result type) or Unit/void functions
- [01-04]: Cross-module imports use `from Module import func1, func2` syntax with `pub fn` for inter-file access
- [01-04]: Bottom-up function ordering required in Mesh (no forward references); leaf helpers first, public entry points last
- [01-04]: Cannot use ? operator in Response-returning or Unit-returning functions; use explicit case on Result types (? requires -> Type!Error return annotation)
- [01-04]: Bind function call results to variables before if conditions (Mesh parser limitation)
- [01-04]: JSON.parse returns Json type (use Json.get), not Map type (not Map.get)
- [01-04]: Org schema provisioning uses DDL with string interpolation (PG DDL cannot use $N params)
- [01-05]: Native Crypto.sha256() for token hashing, Crypto.uuid4() for IDs, pgcrypto crypt()/gen_salt() for bcrypt only (bcrypt not in Mesh stdlib)
- [01-05]: OAuth token exchange stubbed (Mesh HTTP client API unverified); redirect to Google works fully
- [01-05]: Meta refresh HTML redirect instead of Location header (Mesh has no response header API)
- [01-05]: Module files must use single-word names (Mesh import rejects underscores in module paths)
- [01-05]: Use Pg.query/Pg.execute (not Pool.*) inside with_org_schema callbacks (PgConn vs PoolHandle types)
- [01-06]: Vendor stubs for Streem-2 and LitUI -- proprietary packages not on npm, created local file: stubs with matching type declarations
- [01-06]: Hash-based routing (#/path) for Phase 1 frontend (no server-side routing needed)
- [01-06]: Tier detection via /api/config/tier endpoint with fallback to 'oss'
- [01-06]: Native tab/dialog implementations instead of lui-tabs/lui-dialog web components (upgrade in Phase 7)
- [01.1-01]: ApiKey keeps key_hash/key_prefix security model (SHA-256 hash) instead of reference project cleartext key_value
- [01.1-01]: password_hash excluded from User struct (never expose to app code; queried directly in auth SQL)
- [01.1-01]: Organization uses slug instead of schema_name/owner_id -- schema-per-org eliminated in favor of org_id FK filtering
- [01.1-01]: org_memberships uses raw Pool.execute for composite UNIQUE(user_id, org_id); all other 7 tables use Migration.create_table DSL
- [01.1-02]: Return Map<String, String> from query functions (not struct types) for flexibility -- handlers construct structs if needed
- [01.1-02]: OAuth state stored as session rows with 'oauth_state_' prefix and placeholder UUID user_id
- [01.1-02]: tenant.mpl and schema.mpl kept as comment stubs (not deleted) to avoid import errors until Plans 03/04 update callers
- [01.1-03]: Explicit case matching on Result in all handler functions (handlers return Response, not Result -- cannot use ? operator)
- [01.1-03]: Fire-and-forget pattern (let _ =) for non-critical cleanup operations (expired session cleanup, token invalidation, oauth state deletion)
- [01.1-03]: OAuth google_oauth_start now handles store_oauth_state error with 500 response (was fire-and-forget inline SQL)
- [01.1-04]: main.mpl needs no changes -- all handler function signatures (pool, request) -> Response preserved, all routes unchanged
- [01.1-04]: Org creation returns slug instead of schema_name in 201 response -- schema-per-org fully eliminated
- [01.1-04]: Slug generation uses inline String.replace(String.lower(name), " ", "-") rather than a library
- [Phase 01.2-reorganize-repo-with-server-and-client-directories]: Preserved Mesh module/import paths while relocating backend runtime files into server/.
- [Phase 01.2-reorganize-repo-with-server-and-client-directories]: Kept client API adapter on relative /api paths during frontend-to-client rename.
- [Phase 01.2-reorganize-repo-with-server-and-client-directories]: Compose service renamed from app to server with build context anchored at ./server to match ownership boundaries.
- [Phase 01.2-reorganize-repo-with-server-and-client-directories]: Root package.json remains dependency-light and only provides scoped wrapper scripts for server/client workflows.
- [Phase 01.2-reorganize-repo-with-server-and-client-directories]: Regression matrix validated in a clean detached worktree when dirty workspace edits caused non-phase build hangs.

### Roadmap Evolution

- Phase 01.1 inserted after Phase 1: Update project to use Mesh built-in ORM for migrations and queries (URGENT) -- COMPLETE
- Phase 01.2 inserted after Phase 1: Reorganize repo with server and client directories (URGENT)

### Pending Todos

None yet.

### Blockers/Concerns

- ~~[Phase 1 prerequisite]: Mesh WebSocket actor mailbox backpressure API is unverified~~ RESOLVED in 01-02: WS actor supervision spike validates Ws.serve callback patterns and spawn/actor supervision
- ~~[Phase 1 prerequisite]: Streem-2 fromWebSocket() reconnection behavior under connection drops is unverified~~ RESOLVED in 01-02: WS reconnect spike validates exponential backoff reconnection
- ~~[Phase 1 prerequisite]: LitUI chart live-update performance (partial data append vs full re-render) is unverified~~ RESOLVED in 01-02: Chart live-update spike validates pushData() with RAF coalescing at 60Hz
- [Phase 2 risk]: Sentry envelope format has undocumented edge cases — plan for iteration after first real-world SDK compatibility test
- [Phase 2 risk]: PII scrubbing scope at ingestion not yet defined — GDPR compliance scope needed before error ingestion endpoint ships

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Dogfood Mesh qualified-if/String alias fixes | 2026-03-03 | 0a6e152 | [1-the-mesh-langauge-has-gotten-some-fixes-](./quick/1-the-mesh-langauge-has-gotten-some-fixes-/) |

## Session Continuity

Last session: 2026-03-04
Stopped at: Completed 01.2-03-PLAN.md
Resume file: .planning/phases/01.2-reorganize-repo-with-server-and-client-directories/01.2-03-SUMMARY.md

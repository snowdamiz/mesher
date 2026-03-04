---
phase: 02-error-ingestion-core
plan: 01
subsystem: database
tags: [timescaledb, hypertable, postgresql, migrations, orm, ingestion]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "projects/organizations/api_keys tables, ORM patterns, Config module"
provides:
  - "events TimescaleDB hypertable with 20 columns"
  - "issues table with fingerprint-based deduplication (UNIQUE constraint)"
  - "rate_limit_configs table for per-org rate limiting"
  - "scrub_rules table for per-org PII scrubbing patterns"
  - "IngestEvent, Issue, RateLimitConfig, ScrubRule type structs"
  - "upsert_issue, insert_event, get_rate_limit_config, get_active_scrub_rules, validate_api_key_for_ingest query functions"
  - "Config additions: otlp_port, rate_limit_default_per_minute, rate_limit_default_burst"
affects: [02-02, 02-03, 02-04, 02-05, 02-06]

# Tech tracking
tech-stack:
  added: [timescaledb]
  patterns: [hypertable-for-events, upsert-by-fingerprint, api-key-join-auth]

key-files:
  created:
    - server/migrations/20260304100000_create_ingestion_tables.mpl
    - server/src/types/event.mpl
  modified:
    - server/src/storage/queries.mpl
    - server/src/Config.mpl

key-decisions:
  - "IngestEvent struct derives only Json (not Schema/Row) since it is an in-memory normalization type, not a DB model"
  - "Events table has no PRIMARY KEY on id -- TimescaleDB hypertables require partitioning column in unique indexes"
  - "upsert_issue implements status reset (resolved/ignored -> open) via ON CONFLICT for regression detection"
  - "validate_api_key_for_ingest uses JOIN to resolve project_id + org_id in a single query"

patterns-established:
  - "Hypertable pattern: Pool.execute for CREATE TABLE + SELECT create_hypertable() for time-series tables"
  - "Upsert-by-fingerprint: INSERT ON CONFLICT with RETURNING for deduplicated issue management"
  - "Cross-table auth query: JOIN api_keys with projects for ingestion endpoint authentication"

requirements-completed: [ERR-01, ERR-02, ERR-10]

# Metrics
duration: 3min
completed: 2026-03-04
---

# Phase 02 Plan 01: Data Layer Foundation Summary

**TimescaleDB events hypertable, issues table with fingerprint deduplication, rate limit and scrub rule configs, 4 type structs, and 5 ingestion query functions including upsert-by-fingerprint with status reset**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-04T03:19:32Z
- **Completed:** 2026-03-04T03:23:01Z
- **Tasks:** 2
- **Files modified:** 4 (1 created migration, 1 created types, 2 modified)

## Accomplishments
- Created ingestion migration with 4 tables (issues, events, rate_limit_configs, scrub_rules) and 9 indexes
- Events table converted to TimescaleDB hypertable for time-series query performance
- Defined IngestEvent (in-memory), Issue, RateLimitConfig, ScrubRule type structs
- Added 5 ingestion query functions: upsert_issue (with regression detection), insert_event, get_rate_limit_config, get_active_scrub_rules, validate_api_key_for_ingest
- Config module extended with otlp_port, rate_limit_default_per_minute, rate_limit_default_burst

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ingestion database migration** - `58f9a36` (feat)
2. **Task 2: Define event type structs and add ingestion config + query functions** - `ffecce2` (feat)

**Deviation fix:** `c04b599` (fix: pre-existing ratelimit.mpl compilation errors)

## Files Created/Modified
- `server/migrations/20260304100000_create_ingestion_tables.mpl` - Migration creating events (hypertable), issues, rate_limit_configs, scrub_rules tables
- `server/src/types/event.mpl` - IngestEvent, Issue, RateLimitConfig, ScrubRule struct definitions
- `server/src/storage/queries.mpl` - Added import + 5 new ingestion query functions
- `server/src/Config.mpl` - Added otlp_port, rate_limit_default_per_minute, rate_limit_default_burst

## Decisions Made
- IngestEvent derives only Json (not Schema/Row) -- it is an in-memory normalization struct, not a DB model
- Events table omits PRIMARY KEY on id column -- TimescaleDB requires the partitioning column (timestamp) in any unique constraint
- upsert_issue includes status reset logic (resolved/ignored -> open on new event) for proactive regression detection
- validate_api_key_for_ingest JOINs api_keys with projects to return project_id + org_id in a single DB round-trip

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed pre-existing ratelimit.mpl compilation errors**
- **Found during:** Task 2 verification (build:server)
- **Issue:** `server/src/ingest/ratelimit.mpl` existed as an untracked research artifact with Mesh compilation errors (Int.parse not available, undefined variable from failed parse)
- **Fix:** Moved limit comparison into SQL RETURNING clause as `is_allowed` boolean, adjusted build_rate_result to use string comparison instead of Int.parse
- **Files modified:** server/src/ingest/ratelimit.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** c04b599

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Fix was necessary for build verification. No scope creep -- the file was pre-existing and only needed minimal changes to compile.

## Issues Encountered
None beyond the pre-existing ratelimit.mpl compilation issue documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Data layer foundation complete: tables, types, queries, and config all in place
- Plan 02-02 (Valkey spike + rate limiting + health endpoint) can proceed -- rate_limit_configs table and Config values are ready
- Plan 02-03 (ingestion auth + PII scrubber + fingerprinting) can proceed -- validate_api_key_for_ingest and scrub_rules table are ready
- All subsequent plans in Phase 2 depend on the types and queries established here

## Self-Check: PASSED

- All 5 files verified present on disk
- All 3 commits verified in git history (58f9a36, ffecce2, c04b599)
- `npm run build:server` compiles successfully

---
*Phase: 02-error-ingestion-core*
*Completed: 2026-03-04*

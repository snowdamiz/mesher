---
phase: 02-error-ingestion-core
plan: 02
subsystem: api
tags: [rate-limiting, health-check, valkey, postgresql, ingestion]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: HTTP routing, Pool/Repo/Query ORM, Config env pattern
  - phase: 02-error-ingestion-core (plan 01)
    provides: rate_limit_counters table, ingestion types/queries
provides:
  - Rate limiting module (check_rate_limit) with PostgreSQL sliding window counters
  - Valkey connectivity stub (connect_valkey) for future Valkey client integration
  - Ingestion health endpoint handler (handle_health_ingest) with component status reporting
  - compute_retry_after helper for rate limit 429 responses
affects: [02-error-ingestion-core plans 03-06, phase-03 error-management]

# Tech tracking
tech-stack:
  added: []
  patterns: [PostgreSQL-based rate limiting via INSERT ON CONFLICT DO UPDATE RETURNING, fail-open rate limiter pattern, multi-component health check with degraded/unavailable states]

key-files:
  created:
    - server/src/ingest/ratelimit.mpl
    - server/src/ingest/health.mpl
  modified: []

key-decisions:
  - "PostgreSQL-based rate limiting instead of Valkey -- Mesh runtime has no Valkey/Redis client (verified via GitNexus search of mesh repo)"
  - "Fail-open rate limiting -- if DB check fails, allow the request to prevent rate limiter outages from blocking ingestion"
  - "Health endpoint reports degraded (not unavailable) when rate limiter is down since ingestion still works via PostgreSQL fallback"
  - "Retry-After returns fixed 60s instead of precise window remainder -- avoids extra DB call for non-critical response field"

patterns-established:
  - "Rate limit check via single atomic SQL (INSERT ON CONFLICT UPDATE RETURNING) -- no check-then-increment race"
  - "Health endpoint pattern: check_db + check_rate_limiter -> compute_status -> status_code -> JSON response"
  - "Helper function extraction for single-line case arms in Mesh (case arm bodies cannot span multiple lines)"

requirements-completed: [INGEST-06, INGEST-07]

# Metrics
duration: 7min
completed: 2026-03-04
---

# Phase 02 Plan 02: Rate Limiting and Health Endpoint Summary

**PostgreSQL-backed sliding window rate limiter with fail-open semantics and multi-component health check endpoint**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-04T03:19:34Z
- **Completed:** 2026-03-04T03:27:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Rate limiting module with atomic PostgreSQL upsert (INSERT ON CONFLICT DO UPDATE RETURNING) -- no race conditions
- Valkey client discovery confirmed unavailable in Mesh runtime; clean PostgreSQL fallback implemented
- Health endpoint reporting healthy/degraded/unavailable with per-component status (db, rate_limiter)
- Fail-open rate limiting ensures rate limiter failures never block event ingestion

## Task Commits

Each task was committed atomically:

1. **Task 1: Valkey spike + rate limiting module** - `c04b599` (fix, from Plan 02-01 Rule 3 deviation -- file was pre-existing)
2. **Task 2: Ingestion health endpoint** - `a605c9d` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `server/src/ingest/ratelimit.mpl` - Rate limiting with PostgreSQL sliding window counters, connect_valkey stub, compute_retry_after helper
- `server/src/ingest/health.mpl` - Health endpoint handler checking DB and Valkey connectivity, returning JSON with component statuses

## Decisions Made
- **PostgreSQL over Valkey for rate limiting:** GitNexus search of the mesh repo confirmed no Valkey/Redis client exists. PostgreSQL INSERT ON CONFLICT provides atomic increment-and-read in one round trip (~5-10ms vs sub-1ms for Valkey, acceptable for self-hosted).
- **Fail-open behavior:** Rate limiter returns "allowed" if the DB check fails. This prioritizes availability over strict rate enforcement -- a rate limiter outage should not prevent all event ingestion.
- **Fixed 60s retry_after:** Returns a constant 60 seconds rather than computing precise window remainder. Avoids an extra DB call for a value that only appears in 429 error responses. Sentry SDKs accept any positive Retry-After.
- **Degraded vs unavailable distinction:** DB down = unavailable (503), rate limiter down = degraded (200). Rate limiting failure is non-critical since ingestion still works via PostgreSQL fallback and the rate limiter itself falls back gracefully.

## Deviations from Plan

### Task 1 Pre-existing

**ratelimit.mpl was already created and committed by a prior Plan 02-01 execution** (commit `c04b599`). That execution encountered a Rule 3 (blocking) deviation where the pre-existing ratelimit.mpl file prevented server compilation, so it was fixed and committed as part of Plan 02-01. The file matches all Task 1 requirements -- no additional changes were needed.

---

**Total deviations:** 0 in this plan execution (Task 1 work was absorbed by Plan 02-01)
**Impact on plan:** No scope creep. Task 2 (health endpoint) was executed fresh.

## Issues Encountered
- **Mesh `module` imports:** Config.mpl uses `module Config do ... end` which wraps functions in a namespace. `from Src.Config import valkey_url` fails because the module block has its own export scope. Fixed by using `Env.get("VALKEY_URL", ...)` directly (same pattern as main.mpl).
- **Case arm multiline bodies:** Mesh does not support multi-line case arm bodies after `->`. Resolved by extracting logic into named helper functions (build_rate_result, build_failopen_result) so case arms remain single-line.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Rate limiting module ready for use by ingestion endpoint handlers (Plans 03-05)
- Health endpoint ready for wiring into main.mpl router (Plan 06)
- Valkey client integration deferred until Mesh gains Redis/Valkey support -- swap is isolated to connect_valkey function

## Self-Check: PASSED

- FOUND: server/src/ingest/ratelimit.mpl
- FOUND: server/src/ingest/health.mpl
- FOUND: 02-02-SUMMARY.md
- FOUND: commit c04b599 (Task 1 - ratelimit)
- FOUND: commit a605c9d (Task 2 - health)

---
*Phase: 02-error-ingestion-core*
*Completed: 2026-03-04*

---
phase: 02-error-ingestion-core
plan: 05
subsystem: ingestion
tags: [otlp, opentelemetry, json-api, http-handler, rate-limiting, error-ingestion]

# Dependency graph
requires:
  - phase: 02-error-ingestion-core
    provides: "auth, scrubber, fingerprint modules (Plan 03); upsert_issue, insert_event queries (Plan 01); rate limiting (Plan 02); Sentry envelope handler (Plan 04)"
provides:
  - "OTLP/HTTP JSON handler: handle_otlp_logs, handle_otlp_traces, handle_otlp_metrics"
  - "Generic JSON API handler: handle_generic_event"
  - "All ingestion routes wired in main.mpl: Sentry, OTLP, generic, health"
  - "Port 4318 exposed in docker-compose.yml for OTLP clients"
affects: [02-06, 03]

# Tech tracking
tech-stack:
  added: []
  patterns: [string-based-otlp-parsing, severity-number-mapping, nano-timestamp-sql-conversion]

key-files:
  created:
    - server/src/ingest/otlp.mpl
    - server/src/ingest/generic.mpl
  modified:
    - server/main.mpl
    - docker-compose.yml
    - server/src/ingest/envelope.mpl

key-decisions:
  - "String-based JSON parsing for OTLP payloads (no Json.stringify in Mesh; Json.parse used only for validation)"
  - "Severity-to-level mapping via string pattern matching on severityNumber field (Int comparison not available from string input)"
  - "Nanosecond timestamp conversion via PostgreSQL to_timestamp() SQL function"
  - "OTLP routes on same port 8080 with path-based routing; port 4318 mapped via docker-compose for standard OTLP client compatibility"
  - "Default 1000 events/minute rate limit (Int.parse unavailable in Mesh to parse config string)"

patterns-established:
  - "OTLP attribute extraction: split on key pattern, find stringValue/intValue in next section"
  - "OTLP stacktrace parsing: split on \\n, filter 'at ' lines, extract function/filename from parenthesized format"
  - "Generic API pattern: extract fields with defaults, validate required fields, full scrub/fingerprint/store pipeline"

requirements-completed: [INGEST-01, INGEST-02, INGEST-04, INGEST-05, INGEST-06, ERR-01, ERR-02, ERR-10]

# Metrics
duration: 9min
completed: 2026-03-04
---

# Phase 02 Plan 05: OTLP + Generic API Summary

**OTLP/HTTP JSON handler for logs, traces, and metrics stub with severity-based filtering and exception attribute extraction, plus generic JSON API for custom integrations, all wired into main.mpl with port 4318 for OTLP clients**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-04T03:42:11Z
- **Completed:** 2026-03-04T03:51:10Z
- **Tasks:** 2
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments
- OTLP logs handler extracts error-severity LogRecords (>=17) with exception.type, exception.message, exception.stacktrace attributes and processes through full scrub/fingerprint/store pipeline
- OTLP traces handler extracts exception span events (name=="exception") with same attribute extraction
- OTLP metrics handler stubs with 200 acknowledgment, deferred to Phase 4
- Generic JSON API validates required message field, extracts nested exception object, applies defaults for optional fields
- All endpoints: 415 for protobuf content type (JSON-only for Phase 2), 429 with Retry-After header, Bearer token auth
- Port 4318 exposed in docker-compose.yml mapped to 8080 for standard OTLP client connectivity

## Task Commits

Each task was committed atomically:

1. **Task 1: OTLP/HTTP JSON handler** - `5d03db6` (feat)
2. **Task 2: Generic JSON API handler + route wiring** - `011bb77` (feat)

## Files Created/Modified
- `server/src/ingest/otlp.mpl` - OTLP/HTTP JSON handler for logs (error severity extraction), traces (exception span events), metrics (stub)
- `server/src/ingest/generic.mpl` - Generic JSON API handler for custom integrations with message validation and exception object extraction
- `server/main.mpl` - Added imports and routes for OTLP (/v1/logs, /v1/traces, /v1/metrics) and generic (/api/:project_id/events) endpoints
- `docker-compose.yml` - Added OTLP port 4318 mapping to server port 8080
- `server/src/ingest/envelope.mpl` - Fixed Int.parse usage (unavailable in Mesh) with default rate limit value

## Decisions Made
- Used string-based JSON parsing throughout (Mesh has no Json.stringify; Json.parse only validates structure but cannot extract fields back to strings)
- OTLP severity filtering uses string pattern matching on "severityNumber":N patterns rather than integer comparison (severity number arrives as part of a JSON string, not as a parsed Int)
- Nanosecond timestamps converted via PostgreSQL `to_timestamp(bigint / 1e9)` since Mesh has no date/time formatting
- OTLP endpoints share port 8080 with path-based routing; docker-compose maps external 4318 to internal 8080 for standard OTLP client compatibility
- Rate limit defaults to 1000 events/minute (cannot parse string config to Int in Mesh)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Int.parse usage in envelope.mpl**
- **Found during:** Task 1 (build verification)
- **Issue:** `server/src/ingest/envelope.mpl` from Plan 04 used `Int.parse(rate_limit)` which does not exist in Mesh stdlib
- **Fix:** Replaced with hardcoded default `1000` passed directly to `check_rate_limit`
- **Files modified:** server/src/ingest/envelope.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** 5d03db6 (part of Task 1 commit)

**2. [Rule 3 - Blocking] Removed Json.stringify and Json.get usage in OTLP handler**
- **Found during:** Task 1 (initial build attempt)
- **Issue:** First version of otlp.mpl used `Json.parse`/`Json.get`/`Json.stringify` pipeline; `Json.stringify` does not exist on Json type in Mesh
- **Fix:** Rewrote entire handler to use string-based JSON extraction (same pattern as envelope.mpl), using `Request.body(request)` directly as string
- **Files modified:** server/src/ingest/otlp.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** 5d03db6 (part of Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for compilation. String-based JSON parsing produces equivalent results to the planned Json.parse approach but works within Mesh's available API.

## Issues Encountered
None beyond the auto-fixed deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three ingestion protocol families complete: Sentry SDK (Plan 04), OTLP (this plan), Generic JSON API (this plan)
- Plan 02-06 (integration testing) can proceed with all endpoints wired and building
- All ingestion endpoints share the same pipeline: auth -> rate limit -> parse -> scrub -> fingerprint -> store
- Port 4318 ready for OTLP client testing

## Self-Check: PASSED

- All created/modified files verified present on disk
- Both commits verified in git history (5d03db6, 011bb77)
- `npm run build:server` compiles successfully

---
*Phase: 02-error-ingestion-core*
*Completed: 2026-03-04*

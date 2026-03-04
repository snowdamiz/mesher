---
phase: 02-error-ingestion-core
plan: 03
subsystem: ingestion
tags: [api-key-auth, pii-scrubbing, fingerprinting, sha256, sentry-compat, deduplication]

# Dependency graph
requires:
  - phase: 02-error-ingestion-core
    provides: "api_keys table, projects table, scrub_rules table, validate_api_key_for_ingest and get_active_scrub_rules query functions"
  - phase: 01-foundation
    provides: "Crypto.sha256, Request.header/query patterns, String.split/contains/replace utilities"
provides:
  - "extract_and_validate_api_key: API key extraction from X-Sentry-Auth, query param, or Bearer header with SHA-256 hash validation"
  - "scrub_event_fields: PII scrubbing pipeline with 17 default sensitive key patterns + custom per-org rules from DB"
  - "compute_fingerprint: SHA-256 fingerprint from exception type + top 5 normalized app frames (line numbers stripped, node_modules excluded)"
  - "compute_fingerprint_with_fallback: fingerprint with message fallback when no stack trace available"
affects: [02-04, 02-05, 02-06]

# Tech tracking
tech-stack:
  added: []
  patterns: [list-filter-for-search, index-based-iteration, string-based-pii-scrubbing, reverse-traversal-fingerprinting]

key-files:
  created:
    - server/src/ingest/auth.mpl
    - server/src/ingest/scrubber.mpl
    - server/src/ingest/fingerprint.mpl
  modified: []

key-decisions:
  - "List.filter used for X-Sentry-Auth header parsing instead of list destructuring (Mesh does not support [head|tail] pattern matching)"
  - "PII scrubbing uses String-based pattern matching (no regex in Mesh stdlib); covers 17 sensitive key patterns + auth headers"
  - "Fingerprint processes frames from end of array (Sentry format is oldest-to-newest) to get most recent frames first"
  - "No list construction with cons operator in Mesh; all list building uses split/filter/map operations"

patterns-established:
  - "Index-based recursive iteration: use List.get(items, idx) with recursive fn(items, idx, len) pattern for list traversal"
  - "String-based JSON field extraction: split on key pattern, then split on closing quote to get value"
  - "Reverse-order frame collection: process from idx=len-1 downward to get most recent frames first without List.reverse"

requirements-completed: [INGEST-05, ERR-01, ERR-02]

# Metrics
duration: 6min
completed: 2026-03-04
---

# Phase 02 Plan 03: Auth, Scrubber, Fingerprint Summary

**API key authentication with 3 extraction methods (X-Sentry-Auth/query param/Bearer), PII scrubbing pipeline with 17 sensitive key patterns + custom org rules, and SHA-256 fingerprinting from exception type + top 5 normalized app frames**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-04T03:30:40Z
- **Completed:** 2026-03-04T03:37:24Z
- **Tasks:** 2
- **Files modified:** 3 (3 created)

## Accomplishments
- API key authentication module supporting X-Sentry-Auth header, sentry_key query parameter, and Authorization Bearer header extraction methods
- PII scrubbing pipeline with 17 hardcoded sensitive key patterns (password, token, secret, cookie, credit card, SSN, etc.) plus custom per-org rules from the scrub_rules database table
- Event fingerprinting algorithm producing SHA-256 hashes from exception type + top 5 normalized application frames (line numbers stripped, node_modules framework frames excluded)
- Fallback fingerprint on exception_type + message when stack trace is empty or has no app frames

## Task Commits

Each task was committed atomically:

1. **Task 1: API key authentication module for ingestion** - `087aa43` (feat)
2. **Task 2: PII scrubber and fingerprinting modules** - `8dc0e78` (feat)

## Files Created/Modified
- `server/src/ingest/auth.mpl` - API key extraction (3 methods) and SHA-256 hash validation against api_keys table
- `server/src/ingest/scrubber.mpl` - PII scrubbing pipeline with default sensitive key patterns + custom per-org rules
- `server/src/ingest/fingerprint.mpl` - Event fingerprinting with app frame normalization and fallback

## Decisions Made
- Used `List.filter` for finding sentry_key in X-Sentry-Auth header pairs instead of list destructuring (Mesh does not support `[head|tail]` cons syntax)
- PII scrubbing implemented with String.contains/String.replace for literal pattern matching since Mesh stdlib has no regex support; covers sensitive JSON keys and auth header values
- Fingerprint module processes frames from end of array (reverse order) to get most recent frames first (Sentry orders oldest-to-newest); avoids needing List.reverse which may not exist
- All list building uses existing List operations (split/filter/map) rather than cons operator construction

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed reserved word `after` used as variable name**
- **Found during:** Task 2 (fingerprint module)
- **Issue:** `let after = List.last(parts)` failed to parse because `after` is a reserved keyword in Mesh
- **Fix:** Renamed variable to `rest_str`
- **Files modified:** server/src/ingest/fingerprint.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** 8dc0e78 (part of Task 2 commit)

**2. [Rule 3 - Blocking] Rewrote list construction to avoid unsupported cons operator**
- **Found during:** Task 2 (both scrubber and fingerprint modules)
- **Issue:** `[item | rest_list]` list construction syntax is not supported in Mesh; parse errors on `|` in list literals
- **Fix:** Rewrote all algorithms to use index-based iteration (List.get + recursive functions) and String.split/filter/map instead of building lists with cons
- **Files modified:** server/src/ingest/scrubber.mpl, server/src/ingest/fingerprint.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** 8dc0e78 (part of Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for compilation. No scope creep -- algorithms produce identical results using available Mesh idioms.

## Issues Encountered
None beyond the auto-fixed deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three core processing modules are ready for protocol handler integration
- Plan 02-04 (Sentry envelope handler) can import extract_and_validate_api_key, scrub_event_fields, and compute_fingerprint
- Plan 02-05 (OTLP handler) can use the same modules
- Plan 02-06 (generic JSON API) can use the same modules
- Pipeline sequence established: authenticate -> scrub -> fingerprint -> store

## Self-Check: PASSED

- All 4 files verified present on disk
- All 2 commits verified in git history (087aa43, 8dc0e78)
- `npm run build:server` compiles successfully

---
*Phase: 02-error-ingestion-core*
*Completed: 2026-03-04*

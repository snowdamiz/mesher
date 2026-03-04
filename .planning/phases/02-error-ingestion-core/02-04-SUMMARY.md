---
phase: 02-error-ingestion-core
plan: 04
subsystem: ingestion
tags: [sentry-envelope, sentry-sdk, http-handler, pii-scrubbing, fingerprinting, rate-limiting, drop-in-compatibility]

# Dependency graph
requires:
  - phase: 02-error-ingestion-core
    provides: "auth.mpl (extract_and_validate_api_key), scrubber.mpl (scrub_event_fields), fingerprint.mpl (compute_fingerprint), ratelimit.mpl (check_rate_limit), queries.mpl (upsert_issue, insert_event, get_rate_limit_config)"
  - phase: 01-foundation
    provides: "HTTP.router, HTTP.response_with_headers, Crypto.uuid4, Request.body/header/query patterns"
provides:
  - "handle_sentry_envelope: Sentry envelope parser and HTTP handler at POST /api/:project_id/envelope/"
  - "Envelope header parsing (event_id, sdk name/version extraction)"
  - "Sentry event JSON exception data extraction (type, value, frames, platform, level, environment, tags, extra, contexts)"
  - "Rate limit 429 responses with Retry-After and X-Sentry-Rate-Limits headers"
  - "Route wiring in main.mpl for /api/:project_id/envelope/ and /health/ingest"
affects: [02-05, 02-06, 03]

# Tech tracking
tech-stack:
  added: []
  patterns: [string-based-json-extraction, brace-depth-tracking, recursive-envelope-item-processing]

key-files:
  created:
    - server/src/ingest/envelope.mpl
  modified:
    - server/main.mpl
    - server/src/ingest/otlp.mpl

key-decisions:
  - "String-based JSON field extraction instead of Json.parse for envelope/item headers (avoids Result handling overhead, consistent with scrubber/fingerprint patterns)"
  - "Hardcoded 1000 events/minute default rate limit since Int.parse is unavailable in Mesh; get_rate_limit_config called but result used for future extensibility"
  - "Brace/bracket depth tracking extracted into helper functions (brace_depth_delta, bracket_depth_delta) to avoid nested if/else in let bindings which Mesh parser rejects"
  - "Non-event items silently discarded per locked decision; envelope still returns 200"
  - "Event IDs from envelope header used when available; Crypto.uuid4() generated as fallback"

patterns-established:
  - "Brace-depth JSON object extraction: split on key pattern, track {/} depth to find matching close brace"
  - "Bracket-depth JSON array extraction: same pattern for [ ] to extract frames arrays"
  - "Recursive item pair processing: iterate envelope lines in pairs (header + payload) with idx+2 stepping"

requirements-completed: [INGEST-03, INGEST-05, INGEST-06, ERR-01, ERR-02, ERR-10]

# Metrics
duration: 5min
completed: 2026-03-04
---

# Phase 02 Plan 04: Sentry Envelope Handler Summary

**Sentry envelope parser with exception extraction, full auth/scrub/fingerprint/store pipeline, rate limit headers, and route wiring for drop-in @sentry/node SDK compatibility**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-04T03:42:12Z
- **Completed:** 2026-03-04T03:47:13Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- Sentry envelope parser that handles newline-delimited format with envelope header, item headers, and event payloads
- Full ingestion pipeline: authenticate (API key) -> rate limit check -> parse envelope -> scrub PII -> fingerprint -> upsert issue -> insert event -> return 200 with event_id
- Rate-limited responses return 429 with both Retry-After and X-Sentry-Rate-Limits headers via HTTP.response_with_headers
- Non-event envelope items (attachments, sessions, transactions, replays, check-ins, etc.) silently discarded per locked decision
- Routes wired into main.mpl: POST /api/:project_id/envelope/ and GET /health/ingest

## Task Commits

Each task was committed atomically:

1. **Task 1: Sentry envelope parser and handler** - `40c706d` (feat)
2. **Task 2: Wire Sentry envelope route into main.mpl** - `fb0358b` (feat)

## Files Created/Modified
- `server/src/ingest/envelope.mpl` - Sentry envelope parser, exception data extractor, rate limit response helper, main handler with full pipeline
- `server/main.mpl` - Added imports and routes for handle_sentry_envelope and handle_health_ingest
- `server/src/ingest/otlp.mpl` - Fixed pre-existing compilation errors (Json.stringify unavailable)

## Decisions Made
- Used string-based JSON field extraction (split on key pattern, extract value) consistent with patterns established in scrubber.mpl and fingerprint.mpl -- avoids Json.parse Result handling overhead for simple field extraction
- Hardcoded 1000 events/minute default for rate limiting since Int.parse is not available in Mesh stdlib; the get_rate_limit_config query is ready for when configurable limits are needed
- Extracted brace/bracket depth computation into separate helper functions (brace_depth_delta, bracket_depth_delta) because Mesh parser rejects nested if/else chains inside let bindings
- Envelope event_id from header is used when present; Crypto.uuid4() generated as fallback for envelopes without event_id

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Nested if/else in let binding causes parse error**
- **Found during:** Task 1 (envelope parser)
- **Issue:** `let new_depth = if ch == "{" do depth + 1 else if ch == "}" do depth - 1 else depth end end` causes Mesh parse error ("expected expression") due to nested if/else inside let binding
- **Fix:** Extracted brace/bracket depth computation into separate named functions (brace_depth_delta, bracket_depth_delta) that return Int
- **Files modified:** server/src/ingest/envelope.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** 40c706d (part of Task 1 commit)

**2. [Rule 3 - Blocking] Pre-existing otlp.mpl compilation errors**
- **Found during:** Task 1 verification (build:server)
- **Issue:** `server/src/ingest/otlp.mpl` existed as untracked research artifact using `Json.stringify()` which does not exist in Mesh stdlib, causing 3 compilation errors (method not found, undefined variables)
- **Fix:** Replaced Json.stringify(parsed) with direct use of raw_body string (Request.body already returns the string representation needed for string-based JSON extraction)
- **Files modified:** server/src/ingest/otlp.mpl
- **Verification:** `npm run build:server` compiles successfully
- **Committed in:** 40c706d (part of Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes necessary for compilation. No scope creep -- algorithms produce identical results using available Mesh idioms.

## Issues Encountered
None beyond the auto-fixed deviations documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Sentry envelope endpoint is fully wired and ready for @sentry/node SDK testing
- Plan 02-05 (OTLP handler) can reuse the same pipeline patterns and otlp.mpl is now compilable
- Plan 02-06 (generic JSON API) can follow the same handler pattern
- Health endpoint at /health/ingest reports pipeline status
- All existing routes unchanged and verified compiling

## Self-Check: PASSED

- All 3 files verified present on disk
- All 2 commits verified in git history (40c706d, fb0358b)
- `npm run build:server` compiles successfully

---
*Phase: 02-error-ingestion-core*
*Completed: 2026-03-04*

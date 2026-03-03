---
phase: 01-foundation-toolchain-spike
plan: 04
subsystem: api
tags: [mesh, postgresql, multi-tenant, org-crud, schema-provisioning]

# Dependency graph
requires:
  - phase: 01-foundation-toolchain-spike
    provides: [health endpoint, PG pool setup, tenant schema DDL patterns]
provides:
  - Organization CRUD API endpoints (POST/GET /api/orgs, GET /api/orgs/:org_id)
  - Per-org schema provisioning (projects + api_keys tables)
  - Session-based auth check for org handlers
  - Org membership enforcement on detail endpoint
affects: [02-core-data-model, 03-project-crud, 04-api-key-management]

# Tech tracking
tech-stack:
  added: []
  patterns: [cross-module imports with pub fn, bottom-up function ordering, Pool.query for reads / Pg.execute for writes in transactions]

key-files:
  created:
    - src/org/handlers.mpl
    - src/org/schema.mpl
  modified:
    - src/main.mpl

key-decisions:
  - "Used cross-module imports (import Org.Handlers / import Org.Schema) for code organization"
  - "Handlers return Response type explicitly; avoid ? operator in Response-returning fns"
  - "Cookie-based session auth parsed via String.split iterative search (no String.index_of in Mesh)"
  - "Org schema provisioning uses DDL with string interpolation since PG DDL cannot use $N params"
  - "Bottom-up function ordering required: Mesh has no forward references"

patterns-established:
  - "Module pattern: pub fn for cross-file access, import X.Y then Y.func()"
  - "Function ordering: leaf helpers first, public entry points last (no forward refs)"
  - "If-condition pattern: bind function call results to variables before using in if conditions"
  - "Response handlers: use explicit case/if instead of ? operator"
  - "Transaction pattern: Pool.checkout -> Pg.begin -> Pg.execute -> Pg.commit -> Pool.checkin"

requirements-completed: [ORG-06]

# Metrics
duration: 25min
completed: 2026-03-03
---

# Phase 01 Plan 04: Organization CRUD with Schema Provisioning Summary

**Org CRUD endpoints (create/list/get) with per-org PG schema provisioning and session-based auth checks using Mesh cross-module imports**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-03T03:48:00Z
- **Completed:** 2026-03-03T04:13:00Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- Created org CRUD API: POST /api/orgs (create), GET /api/orgs (list), GET /api/orgs/:org_id (detail)
- Per-org schema provisioning creates dedicated PG schema with projects and api_keys tables
- Session-based auth extracts user_id from session_id cookie via sessions table lookup
- Membership enforcement: GET /api/orgs/:org_id returns 403 if user is not a member

## Task Commits

Each task was committed atomically:

1. **Task 1: Create org handlers, schema provisioner, and wire routes** - `2e9380a` (feat)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `src/org/handlers.mpl` - Organization HTTP handlers (create, list, get) with session auth and membership checks
- `src/org/schema.mpl` - Per-org PostgreSQL schema provisioning (projects + api_keys tables)
- `src/main.mpl` - Added org route wiring via import Org.Handlers

## Decisions Made
- **Cross-module imports:** Used `import Org.Handlers` / `import Org.Schema` with `pub fn` for inter-file access, which is the correct Mesh module pattern (not direct function calls across files)
- **No forward references:** Mesh requires all called functions to be defined before the caller; used strict bottom-up ordering
- **Result handling in Response fns:** Cannot use `?` operator in functions returning `Response`; used explicit `case` pattern matching on `Result` types with error-specific HTTP responses
- **Cookie parsing:** Implemented iterative search via `String.split` + `List.get` since `String.index_of` does not exist in Mesh stdlib
- **If-condition limitation:** Function calls cannot be used directly as `if` conditions in Mesh; must bind to variables first (e.g., `let sw = String.starts_with(x, y)` then `if sw do`)
- **Json.get for parsed JSON:** `JSON.parse` returns `Json` type, not `Map`; field access uses `Json.get(obj, "field")` not `Map.get`

## Deviations from Plan

### Discoveries (Mesh Language Constraints)

**1. [Rule 1 - Bug] No forward references in Mesh**
- **Found during:** Task 1 (compilation)
- **Issue:** Mesh compiler resolves functions top-to-bottom; calling a function defined later produces "unbound variable" error
- **Fix:** Reorganized all functions in strict bottom-up order (leaf helpers first, public entry points last)
- **Committed in:** 2e9380a

**2. [Rule 1 - Bug] Function calls in if-conditions cause parse errors**
- **Found during:** Task 1 (compilation)
- **Issue:** `if String.starts_with(x, "hello") do` fails with parse error; also `if is_long(x) do` fails
- **Fix:** Bind function call results to variables before using in `if` conditions
- **Committed in:** 2e9380a

**3. [Rule 1 - Bug] ? operator incompatible with Response return type**
- **Found during:** Task 1 (compilation)
- **Issue:** `?` requires function to return `Result` or `Option`, not `Response`
- **Fix:** Replaced all `?` usage in Response-returning functions with explicit `case` on Result
- **Committed in:** 2e9380a

**4. [Rule 1 - Bug] JSON.parse returns Json type, not Map**
- **Found during:** Task 1 (compilation)
- **Issue:** `Map.get` on `JSON.parse` result fails with "expected Map, found Json"
- **Fix:** Use `Json.get(body_json, "name")` instead of `Map.get`
- **Committed in:** 2e9380a

---

**Total deviations:** 4 auto-fixed (all Rule 1 - bugs / language constraint discoveries)
**Impact on plan:** All discoveries necessary for correct Mesh compilation. Patterns documented for future plans.

## Deferred Issues

- **auth/session.mpl compilation errors:** The pre-existing auth session file (from Plan 03) has forward reference issues, pipe-chain patterns in case arms, and type mismatches that prevent full project compilation. These are out of scope for Plan 04. When Plan 03 is properly executed/fixed, these should be addressed.

## Issues Encountered
- Extensive Mesh compiler exploration was needed to discover the actual PG result API (`Pool.query` returns `List<Map<String, String>>`), HTTP handler patterns, and module import syntax. The Mesh language has zero public documentation, requiring source-code-level investigation of the compiler.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Org CRUD handlers ready for integration with auth middleware (Plan 03)
- Schema provisioning pattern established for future tenant-scoped tables
- The `auth/session.mpl` file needs compilation fixes before full project builds succeed

## Self-Check: PASSED

- [x] FOUND: src/org/handlers.mpl
- [x] FOUND: src/org/schema.mpl
- [x] FOUND: src/main.mpl
- [x] FOUND: 01-04-SUMMARY.md
- [x] FOUND: commit 2e9380a

---
*Phase: 01-foundation-toolchain-spike*
*Completed: 2026-03-03*

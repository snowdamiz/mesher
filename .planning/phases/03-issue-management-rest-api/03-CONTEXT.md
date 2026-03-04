# Phase 3: Issue Management + REST API - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can view, filter, search, and manage the lifecycle of grouped error issues through a stable REST API. Covers issue list with sparkline, detail view, event list, status transitions (single and bulk), filtering by project/severity/environment/status/time, and message search. Real-time push is Phase 5; frontend UI is Phase 7.

Requirements: ERR-03, ERR-04, ERR-05, ERR-06, ERR-07, ERR-08, ERR-09

</domain>

<decisions>
## Implementation Decisions

### REST API structure
- Project-scoped URLs following existing pattern: `/api/orgs/:org_id/projects/:project_id/issues`
- Issue detail: `GET /issues/:id` returns issue metadata only
- Issue events: `GET /issues/:id/events` returns paginated event list (separate from detail)
- Cursor-based pagination using last_seen/issue ID as cursor; response includes `next_cursor`
- Metadata envelope response format: `{ data: [...], meta: { total_count, next_cursor, filters_applied } }`

### Issue list data shape
- Default sort: last_seen DESC (most recently active first)
- Sortable columns: last_seen, first_seen, event_count, level via `?sort_by=...&sort_dir=...`
- Sparkline: 24 hourly buckets covering the last 24 hours (24 data points per issue)
- Fields per list item: id, title, level, status, first_seen, last_seen, event_count, environment, sparkline_data

### Filtering & search
- All filters via query params with AND logic: `?status=open&level=error&environment=production`
- Multi-value for same field via comma: `?level=error,warning`
- Message search on same endpoint via `?q=search+term` (searches issue title)
- Default filter: `?status=open` (no project/environment/level/time filter)
- Time range presets: 1h, 24h, 7d, 14d, 30d via `?time_range=24h`

### Issue lifecycle transitions
- Single transition: `PUT /issues/:id` with `{ status: "resolved" }` — idempotent, server validates legal transition
- Bulk updates: `POST /issues/bulk` with `{ action: "resolve", issue_ids: ["id1", "id2", ...] }`
- Max batch size: 100 issues per bulk request (400 if exceeded)
- Partial failure: best-effort — apply what works, return `{ updated: N, failed: [{id, reason}] }`

### Auto-reopen behavior (ERR-05)
- Already implemented in Phase 2 `upsert_issue`: resolved/ignored issues auto-reopen when a new matching event arrives via ON CONFLICT status reset

### Claude's Discretion
- Exact sparkline SQL query (time_bucket or generate_series approach)
- Issue detail endpoint response fields beyond list fields (e.g., latest event metadata)
- Error response format for invalid transitions
- Cursor encoding format (opaque base64 vs plain timestamp)
- Query param parsing approach (given Mesh HTTP stdlib constraints)
- Whether to add `?project_id=` cross-project filtering to org-level route in addition to project-scoped route

</decisions>

<specifics>
## Specific Ideas

- Follows Sentry's pattern: last-seen sort, open-by-default filter, hourly sparkline
- Envelope response format keeps API extensible for future metadata (rate limit info, filter suggestions)
- Separate events endpoint from issue detail keeps responses lean and avoids N+1 in list views

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Issue` struct (`server/src/types/event.mpl`): Already has id, project_id, fingerprint, title, level, status, first_seen, last_seen, event_count, environment, metadata_json — all fields needed for list response
- `upsert_issue` (`server/src/storage/queries.mpl`): Handles insert + auto-reopen regression detection via ON CONFLICT
- `insert_event` (`server/src/storage/queries.mpl`): Events already stored with all fields needed for event detail view
- `validate_session` + `check_membership`: Existing auth chain for session-based routes
- `HTTP.router()` pattern in `main.mpl`: Project-scoped route nesting already established

### Established Patterns
- ORM: `Query.from()`, `Query.where()`, `Query.where_raw()`, `Query.select_raw()`, `Query.order_by_raw()`, `Query.join_as()` — all needed for filtered issue queries
- Return `Map<String, String>` from query functions; handlers construct JSON responses
- Two-step pattern for NOW() timestamps (`Repo.query_raw` then ORM operation)
- Session auth via cookie token validated in handler functions
- `Repo.query_raw` for complex SQL (upserts, aggregations) — will be needed for sparkline queries and bulk updates

### Integration Points
- `server/main.mpl`: Add issue list, detail, events, status update, and bulk routes to router
- `server/src/storage/queries.mpl`: Add query functions for filtered issue list, issue detail, event list, sparkline aggregation, status update, bulk update
- `server/src/types/event.mpl`: Issue struct already sufficient; no new structs needed for Phase 3
- New handler module needed: `server/src/issue/` or similar for issue management handlers

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-issue-management-rest-api*
*Context gathered: 2026-03-04*

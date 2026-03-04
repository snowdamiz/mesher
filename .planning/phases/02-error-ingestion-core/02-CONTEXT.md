# Phase 2: Error Ingestion Core - Context

**Gathered:** 2026-03-03
**Status:** Ready for planning

<domain>
## Phase Boundary

The system accepts error events via OTLP/HTTP (protobuf + JSON) and Sentry envelope format, authenticates them via project-scoped API keys/DSNs, scrubs PII at ingestion, fingerprints events into deduplicated issues, and persists them with environment tagging. Per-org rate limiting enforced with configurable limits via admin UI. A generic JSON API is also available for custom integrations. Health endpoint reports ingestion pipeline status.

Requirements: INGEST-01, INGEST-02, INGEST-03, INGEST-04, INGEST-05, INGEST-06, INGEST-07, ERR-01, ERR-02, ERR-10

</domain>

<decisions>
## Implementation Decisions

### Sentry SDK compatibility
- Target **@sentry/node (JavaScript) only** for day-1 compatibility testing
- Unsupported envelope item types (attachments, sessions, replays, check-ins): **silently discard** — accept the envelope, process error/event items, drop everything else, return 200
- **Full Sentry-compatible response format**: return X-Sentry-Rate-Limits headers, Retry-After on 429, event_id in response body — SDKs behave best with familiar responses
- DSN format: **Sentry-compatible** — `https://<public_key>@<host>/api/<project_id>` — drop-in replacement, user just changes the DSN string in Sentry.init()
- The public_key in the DSN maps to the existing API key system (key_prefix or raw key, validated against key_hash)

### OTLP/HTTP support
- Accept **both protobuf and JSON** content types (application/x-protobuf primary, application/json fallback)
- OTLP endpoint on port 4318 per spec
- INGEST-02 (metrics via OTLP) endpoint is built in this phase but metrics storage/processing is Phase 4 — accept and acknowledge metrics payloads, store raw or defer processing

### Onboarding UX
- When a user creates a project and gets a DSN, the UI shows **copy-paste setup code snippets** with DSN pre-filled for supported SDKs (@sentry/node for Phase 2)
- Makes first-event-received experience fast and guided

### Rate limiting
- Configurable per-org via **admin UI** in org settings
- Default limits applied, administrators can adjust per their hardware/needs

### PII handling
- **Scrub at ingestion time** — PII never hits disk unscrubbed
- Default scrubbing rules: IP addresses, cookies, authorization headers, request bodies
- **Configurable scrubbing rules**: admin can add custom patterns (e.g., SSN regex, credit card patterns) beyond defaults
- Scrubbed values replaced with **`[Filtered]`** placeholder — user can see data existed but was removed (Sentry convention)

### Claude's Discretion
- OTLP authentication mechanism (Authorization header vs custom header — decide based on what OpenTelemetry exporters support)
- Generic JSON API design (separate /api/{project_id}/events endpoint vs reusing OTLP — decide based on simplest custom integration path)
- Rate limiting scope (per-org vs per-project within org budget — match INGEST-06 spec)
- Rate limiting state storage (in-memory vs Valkey-backed — decide based on deployment model)
- 429 response detail level (minimal vs usage info — balance SDK expectations with security)
- PII scrubbing rule granularity (per-org vs per-project — decide what's reasonable for Phase 2)
- Fingerprinting algorithm details (how to detect app frames vs framework frames for JS stack traces, normalization approach)
- Event storage schema design
- Ingestion pipeline actor topology

</decisions>

<specifics>
## Specific Ideas

- DSN is Sentry-compatible so users literally just change the DSN string in their existing Sentry.init() call — zero other code changes
- Unsupported Sentry envelope items are silently discarded, not rejected — the SDK should never see an error for sending sessions/attachments alongside errors
- PII scrubbing uses `[Filtered]` placeholder, matching Sentry's convention — users who migrate from Sentry see familiar behavior
- Setup snippets in the UI after project creation — first-event-received should be achievable in under 5 minutes

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ApiKey` struct (`server/src/types/project.mpl`): key_hash (SHA-256) + key_prefix model — DSN authentication will validate against this
- `queries.mpl` (`server/src/storage/queries.mpl`): Centralized query layer with Repo/Query ORM pattern — new event/issue queries follow same pattern
- `Project` struct with org_id FK: Ingestion endpoints authenticate to a project, all events scoped via project → org chain
- `HTTP.router()` pattern in `main.mpl`: New ingestion routes (Sentry envelope, OTLP, generic API, health) added to same router
- Valkey in Docker Compose stack (not yet used) — available for rate limiting state if chosen

### Established Patterns
- ORM: `Repo.insert`, `Repo.all`, `Query.from`, `Query.where_raw` with `__table__()` convention
- Return type: `Map<String, String>` from query functions, structs with `deriving(Schema, Json, Row)`
- Auth: Session token in cookie, validated via `validate_session` — ingestion endpoints use API key auth instead
- Module imports: `from Src.Module import func` with `pub fn`
- Two-step pattern for pgcrypto/timestamps: `Repo.query_raw` then ORM operation
- Config via env vars: `Env.get("KEY", "default")`

### Integration Points
- `main.mpl` router: Add Sentry envelope route `/api/:project_id/envelope/`, OTLP routes, generic API route, `/health/ingest`
- `server/src/types/`: New structs needed — ErrorEvent, Issue (with fingerprint), possibly RateLimitConfig
- `server/src/storage/queries.mpl`: New query functions for event insert, issue upsert-by-fingerprint, rate limit check
- `server/migrations/`: New migration for events table, issues table, rate_limit_configs table
- Port 4318: May need separate HTTP listener for OTLP or routing from main server — Mesh HTTP capabilities determine this

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-error-ingestion-core*
*Context gathered: 2026-03-03*

# Phase 2: Error Ingestion Core - Research

**Researched:** 2026-03-03
**Domain:** Error event ingestion (OTLP/HTTP, Sentry envelope), fingerprinting, PII scrubbing, rate limiting
**Confidence:** MEDIUM-HIGH

## Summary

Phase 2 transforms Mesher from an auth/org management shell into an error tracking system. The phase must accept error events from two protocol families -- Sentry envelope format (for drop-in SDK compatibility) and OTLP/HTTP (for standards-based observability) -- authenticate them via project-scoped API keys, scrub PII at ingestion, fingerprint events into deduplicated issues, and persist them with environment tagging. Rate limiting prevents abuse, and a health endpoint reports pipeline status.

The core challenge is protocol parsing: Sentry envelopes are a custom newline-delimited format with JSON item headers, while OTLP uses protobuf or JSON-encoded protobuf messages. Both must be normalized into a common internal event representation before fingerprinting and storage. The fingerprinting algorithm (exception type + top 3-5 normalized app frames, line numbers stripped) is a well-understood approach used by Sentry, GlitchTip, and Rollbar. Rate limiting via Valkey sliding window counters is the standard approach for distributed rate limiting.

The Mesh language has proven HTTP routing, ORM, JSON parsing, and crypto capabilities in Phase 1. Phase 2 extends these patterns with new ingestion routes, new database tables (events, issues, rate_limit_configs), and a new authentication path (API key auth instead of session cookies). The OTLP protobuf parsing is the highest-risk item -- Mesh's capability to parse binary protobuf is unverified and may require JSON-only OTLP initially or a custom binary parser.

**Primary recommendation:** Build a common `IngestEvent` internal representation first, then implement protocol adapters (Sentry envelope parser, OTLP/JSON parser, generic JSON API) that normalize into it. Fingerprint and persist from the common representation. Start with OTLP/JSON and defer protobuf to a validation spike.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Target **@sentry/node (JavaScript) only** for day-1 compatibility testing
- Unsupported envelope item types (attachments, sessions, replays, check-ins): **silently discard** -- accept the envelope, process error/event items, drop everything else, return 200
- **Full Sentry-compatible response format**: return X-Sentry-Rate-Limits headers, Retry-After on 429, event_id in response body -- SDKs behave best with familiar responses
- DSN format: **Sentry-compatible** -- `https://<public_key>@<host>/api/<project_id>` -- drop-in replacement, user just changes the DSN string in Sentry.init()
- The public_key in the DSN maps to the existing API key system (key_prefix or raw key, validated against key_hash)
- Accept **both protobuf and JSON** content types for OTLP (application/x-protobuf primary, application/json fallback)
- OTLP endpoint on port 4318 per spec
- INGEST-02 (metrics via OTLP) endpoint built but metrics storage/processing deferred to Phase 4 -- accept and acknowledge metrics payloads
- Onboarding UX: copy-paste setup code snippets with DSN pre-filled for @sentry/node
- Rate limiting: configurable per-org via admin UI in org settings
- PII: **Scrub at ingestion time** -- PII never hits disk unscrubbed
- Default scrubbing rules: IP addresses, cookies, authorization headers, request bodies
- **Configurable scrubbing rules**: admin can add custom patterns beyond defaults
- Scrubbed values replaced with **`[Filtered]`** placeholder (Sentry convention)

### Claude's Discretion
- OTLP authentication mechanism (Authorization header vs custom header -- decide based on what OpenTelemetry exporters support)
- Generic JSON API design (separate /api/{project_id}/events endpoint vs reusing OTLP)
- Rate limiting scope (per-org vs per-project within org budget)
- Rate limiting state storage (in-memory vs Valkey-backed)
- 429 response detail level (minimal vs usage info)
- PII scrubbing rule granularity (per-org vs per-project)
- Fingerprinting algorithm details (app frames vs framework frames for JS, normalization approach)
- Event storage schema design
- Ingestion pipeline actor topology

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INGEST-01 | System accepts error events and trace data via OTLP/HTTP on port 4318 (protobuf primary, JSON fallback) | OTLP/HTTP protocol spec, LogRecord structure, ExportLogsServiceRequest format, authentication patterns |
| INGEST-02 | System accepts infrastructure metrics via OTLP/HTTP on port 4318 | Stub endpoint -- accept and acknowledge, defer processing to Phase 4 |
| INGEST-03 | System accepts Sentry SDK events via envelope format at `/api/{project_id}/envelope/` | Sentry envelope spec, X-Sentry-Auth header, envelope item types, event payload JSON structure |
| INGEST-04 | System accepts error events via generic JSON HTTP REST API | Separate `/api/{project_id}/events` endpoint design with simplified JSON schema |
| INGEST-05 | All ingest endpoints authenticate via project-scoped API key or DSN | API key auth via SHA-256 hash lookup, Sentry DSN auth (X-Sentry-Auth, query params), OTLP auth (Authorization header) |
| INGEST-06 | Per-org ingest rate limits with HTTP 429 + Retry-After | Valkey sliding window counter, per-org scope, configurable limits |
| INGEST-07 | `/health/ingest` endpoint reporting pipeline health | Health check endpoint pattern |
| ERR-01 | Capture error events with stack traces, message, severity, exception type, metadata | Event and issue database schema, common IngestEvent representation |
| ERR-02 | Deduplicate events into issues by fingerprint (exception type + normalized top 3-5 app frames) | Fingerprinting algorithm design, SHA-256 hash of normalized components |
| ERR-10 | Tag events with environment string, distinguishable in database | Environment column on events table, indexed for filtering |
</phase_requirements>

## Standard Stack

### Core
| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Mesh ORM (Repo/Query) | Built-in | Event/issue persistence | Established in Phase 1, all data access uses this pattern |
| PostgreSQL + TimescaleDB | PG17 + latest | Event storage, issue dedup | Already in Docker Compose stack, proven in Phase 1 |
| Valkey | 9-alpine | Rate limiting state (sliding window counters) | Already in Docker Compose stack but unused; standard for distributed rate limiting |
| Mesh HTTP (HTTP.router) | Built-in | Ingestion endpoints | Established routing pattern from Phase 1 |
| Mesh Crypto | Built-in | SHA-256 for API key auth + fingerprint hashing | Crypto.sha256() proven in Phase 1 API key system |

### Supporting
| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| Mesh JSON (Json.parse/Json.get) | Built-in | Parse Sentry envelopes, OTLP JSON, generic API | All ingestion endpoints need JSON parsing |
| Mesh String | Built-in | Envelope line splitting, PII regex matching | Envelope parsing, scrubbing |
| Mesh Env | Built-in | Rate limit defaults, OTLP port config | Config.mpl extensions |

### Protobuf Handling (RISK AREA)
| Approach | Tradeoff |
|----------|----------|
| **JSON-only OTLP initially** | Simpler, uses proven Json.parse; protobuf clients fall back to JSON |
| OTLP protobuf binary parsing | Mesh binary parsing capability is UNVERIFIED; may need custom decoder |

**Recommendation:** Start with OTLP/JSON only (Content-Type: application/json). Return HTTP 415 Unsupported Media Type for application/x-protobuf until a spike verifies Mesh binary parsing. This is acceptable per OTLP spec -- servers MAY support both but JSON is the documented fallback.

**Installation:** No new dependencies. All tools are in the existing Docker Compose stack and Mesh stdlib.

## Architecture Patterns

### Recommended Project Structure
```
server/src/
  ingest/
    envelope.mpl      # Sentry envelope parser + handler
    otlp.mpl           # OTLP/HTTP handler (logs + metrics stub)
    generic.mpl        # Generic JSON API handler
    auth.mpl           # API key authentication (separate from session auth)
    scrubber.mpl       # PII scrubbing engine
    fingerprint.mpl    # Event fingerprinting algorithm
    ratelimit.mpl      # Rate limiting logic (Valkey-backed)
    health.mpl         # /health/ingest endpoint
  types/
    event.mpl          # ErrorEvent, Issue, IngestEvent structs
    project.mpl        # (existing) Organization, Project, ApiKey
    user.mpl           # (existing) User, Session, etc.
  storage/
    queries.mpl        # (existing + new event/issue query functions)
```

### Pattern 1: Common Internal Event Representation
**What:** All three ingestion protocols (Sentry envelope, OTLP, generic JSON) normalize into a single `IngestEvent` struct before fingerprinting, scrubbing, and persistence.
**When to use:** Always -- this is the core architectural pattern.
**Example:**
```
# Internal representation after protocol normalization
pub struct IngestEvent do
  event_id :: String           # UUID, generated if not provided
  project_id :: String         # From URL path
  org_id :: String             # Resolved from project
  timestamp :: String          # ISO 8601
  platform :: String           # "javascript", "node", "python", etc.
  level :: String              # "error", "warning", "fatal", "info"
  message :: String            # Human-readable error message
  exception_type :: String     # e.g., "TypeError", "RangeError"
  exception_value :: String    # Exception message text
  stacktrace_json :: String    # Full stack trace as JSON string
  environment :: String        # "production", "staging", "development"
  release :: String            # App version/release tag
  server_name :: String        # Hostname
  tags_json :: String          # Arbitrary tags as JSON string
  extra_json :: String         # Arbitrary extra data as JSON string
  contexts_json :: String      # Runtime/OS/device contexts as JSON string
  sdk_name :: String           # Sending SDK name
  sdk_version :: String        # Sending SDK version
  raw_payload :: String        # Full original payload for debugging
end
```

### Pattern 2: API Key Authentication (Non-Session)
**What:** Ingestion endpoints authenticate via API key (SHA-256 hash lookup) instead of session cookies. Three auth methods supported for Sentry compatibility.
**When to use:** All ingestion endpoints.
**How it works:**
1. **X-Sentry-Auth header:** Parse `Sentry sentry_key=<key>, sentry_version=7, ...` -- extract sentry_key
2. **Query parameter:** `?sentry_key=<key>` on the URL
3. **Authorization header (OTLP):** `Bearer <api_key>` or custom `Authorization: <api_key>`
4. Hash the extracted key with SHA-256, look up in api_keys table WHERE key_hash = hash AND revoked_at IS NULL
5. Join to projects table to get project_id and org_id

**Recommendation for Claude's Discretion (OTLP auth):** Use `Authorization: Bearer <api_key>` header. This is what OpenTelemetry exporters support natively via the `OTEL_EXPORTER_OTLP_HEADERS` environment variable (e.g., `Authorization=Bearer <key>`). No custom header needed.

### Pattern 3: Upsert-by-Fingerprint for Issue Deduplication
**What:** When storing an event, compute its fingerprint hash. Use PostgreSQL INSERT ... ON CONFLICT to either create a new issue or increment the event count on the existing one.
**When to use:** Every event insertion.
**Example SQL pattern:**
```sql
-- Upsert issue by fingerprint
INSERT INTO issues (id, project_id, fingerprint, title, level, first_seen, last_seen, event_count, status)
VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now(), 1, 'open')
ON CONFLICT (project_id, fingerprint)
DO UPDATE SET
  last_seen = now(),
  event_count = issues.event_count + 1,
  status = CASE
    WHEN issues.status IN ('resolved', 'ignored') THEN 'open'
    ELSE issues.status
  END
RETURNING id, status;
```
Note: The status reset (resolved/ignored -> open on new event) implements ERR-05 proactively, which is technically Phase 3. Include it now since it's trivial and prevents data integrity issues.

### Pattern 4: PII Scrubbing Pipeline
**What:** Before persistence, run all string fields through a configurable scrubbing pipeline.
**When to use:** Between normalization and storage, before fingerprinting.
**Scrubbing order matters:** Scrub BEFORE fingerprinting so identical errors with different PII still group together.
**Default rules:**
- IPv4 addresses: `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b` -> `[Filtered]`
- IPv6 addresses: common pattern -> `[Filtered]`
- Email-like patterns in values (not keys): `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}` -> `[Filtered]`
- Cookie values: strip entirely
- Authorization header values: `[Filtered]`
- Request body content: `[Filtered]` (configurable -- some users want request bodies)
- Credit card patterns: `\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b` -> `[Filtered]`

**Recommendation (PII granularity):** Per-org scrubbing rules for Phase 2. Per-project adds complexity without clear value at this stage. Store rules in a `scrub_rules` table with org_id FK.

### Anti-Patterns to Avoid
- **Parsing protobuf in Mesh without verification:** Mesh's binary data handling is unverified. Do NOT attempt protobuf parsing without a spike first. Start with JSON.
- **Storing raw unscrubbed payloads:** The decision is to scrub at ingestion. Even the `raw_payload` debug field must be scrubbed.
- **Single-table event storage without TimescaleDB:** Events will grow fast. Use a hypertable from day one for the events table (not issues -- issues are low-cardinality).
- **Fingerprinting on the full stack trace:** This causes over-grouping. Only use top 3-5 application frames with line numbers stripped.
- **Blocking rate limit checks on DB:** Rate limiting must be fast. Valkey (sub-millisecond) not PostgreSQL (10ms+).
- **Synchronous Sentry-compatible response without event_id:** The @sentry/node SDK expects `{"id": "<event_id>"}` in the response body. Missing this causes SDK warnings.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rate limiting counters | Custom in-memory counter with cleanup | Valkey INCR + EXPIRE (sliding window) | Survives server restarts, works across multiple server instances, atomic operations |
| Sentry envelope parsing | Custom streaming parser | Line-by-line parser with item type dispatch | Envelope format is simple (newline-delimited) but edge cases exist around length headers and compression |
| UUID generation | Custom random string | Crypto.uuid4() | Already proven in Phase 1, cryptographically random |
| SHA-256 hashing | Custom hash | Crypto.sha256() | Already proven in Phase 1 for API key hashing |
| JSON parsing | Custom parser | Json.parse() + Json.get() | Mesh stdlib, proven in Phase 1 |
| Timestamp formatting | Custom formatter | PostgreSQL now()::text | Two-step pattern established in Phase 1 |

**Key insight:** Phase 2 is primarily integration work -- parsing existing protocols, normalizing data, and storing it. The value is in correct protocol implementation, not custom infrastructure.

## Common Pitfalls

### Pitfall 1: Sentry Envelope Newline Handling
**What goes wrong:** The envelope format uses UNIX newlines (`\n`, ASCII 10) to separate header, item headers, and payloads. If the parser splits on `\r\n` or doesn't handle payloads that contain embedded newlines, items get corrupted.
**Why it happens:** Sentry envelope payloads can contain newlines within JSON strings. The item header's `length` field tells you exactly how many bytes to read for the payload.
**How to avoid:** Always use the `length` field from the item header to read payloads. Only fall back to newline-splitting for items that omit the length field (rare, mainly sessions).
**Warning signs:** Events with truncated stack traces, JSON parse errors on item payloads.

### Pitfall 2: Sentry Auth Header Parsing Complexity
**What goes wrong:** SDKs send auth in different ways: X-Sentry-Auth header, query parameters (?sentry_key=...), or DSN in envelope header. The server must handle all three.
**Why it happens:** Different SDK versions and platforms use different auth methods. @sentry/node uses the X-Sentry-Auth header, @sentry/browser uses query params.
**How to avoid:** Implement all three auth extraction methods and try them in order: X-Sentry-Auth header -> query param -> envelope header DSN.
**Warning signs:** 403 errors from SDKs that work with real Sentry.

### Pitfall 3: OTLP Error Events are LogRecords, Not Trace Spans
**What goes wrong:** Implementing OTLP error ingestion by parsing trace spans with exception events, missing that many OTLP exporters send errors as log records.
**Why it happens:** OpenTelemetry has two paths for errors: span events (exception events on spans) and log records (with severity ERROR+). Both are valid.
**How to avoid:** Accept errors from BOTH `/v1/logs` and `/v1/traces` endpoints. Extract exception attributes from span events (exception.type, exception.message, exception.stacktrace) and from log record attributes.
**Warning signs:** Errors from OTLP clients not appearing in the database.

### Pitfall 4: Fingerprint Instability from Line Number Changes
**What goes wrong:** Two deployments of the same code with slightly different line numbers (e.g., added a comment) produce different fingerprints, creating duplicate issues.
**Why it happens:** The fingerprinting algorithm includes line numbers.
**How to avoid:** Strip line numbers and column numbers from stack frames before fingerprinting. Only use filename + function name for each frame. The requirement explicitly states "line numbers stripped."
**Warning signs:** Issue count growing linearly with deployments instead of stabilizing.

### Pitfall 5: Rate Limiting Race Conditions
**What goes wrong:** Under concurrent requests, multiple requests check the rate limit counter, all see it's under the limit, all proceed, and the actual rate far exceeds the configured limit.
**Why it happens:** Check-then-increment is not atomic.
**How to avoid:** Use Valkey INCR atomically -- increment first, check the returned value, reject if over limit. INCR returns the new value atomically.
**Warning signs:** Rate limiting only works under low concurrency.

### Pitfall 6: X-Sentry-Rate-Limits Header Format
**What goes wrong:** SDK stops sending all events or ignores rate limits entirely.
**Why it happens:** The X-Sentry-Rate-Limits header has a specific format: `retry_after:categories:scope:reason_code:namespaces`. SDKs parse this precisely. Getting the format wrong causes SDKs to either ignore the header or apply overly broad limits.
**How to avoid:** Return the header in exact spec format. For error rate limits: `60:error:org:org_quota`. Test with the actual @sentry/node SDK.
**Warning signs:** SDK logs showing "invalid rate limit header" or SDK continuing to send at full rate during limiting.

### Pitfall 7: Mesh Binary Data Parsing
**What goes wrong:** Attempting to parse OTLP protobuf binary in Mesh fails because Mesh string handling is UTF-8 oriented and doesn't handle raw bytes well.
**Why it happens:** Mesh is a high-level language; binary protocol parsing may not be in its stdlib.
**How to avoid:** Start with JSON-only OTLP. Return 415 for protobuf content type. Add protobuf support after verifying Mesh binary capabilities.
**Warning signs:** Garbled data, encoding errors, crashes on binary payloads.

## Code Examples

### Sentry Envelope Parsing (Pseudocode in Mesh Patterns)
```
# Sentry envelope format:
# Line 1: envelope header JSON ({"event_id":"...", "dsn":"...", "sent_at":"..."})
# Line 2: item header JSON ({"type":"event", "length":1234})
# Line 3-N: item payload (JSON for events, binary for attachments)
# Line N+1: next item header (or EOF)

# Parse approach:
# 1. Split on first \n to get envelope header
# 2. Parse envelope header JSON for event_id, dsn (optional auth)
# 3. Loop: parse item header, read `length` bytes for payload
# 4. Dispatch on item type: "event" -> process, others -> discard

fn parse_envelope(body :: String) -> List<Map<String, String>>!String do
  let lines = String.split(body, "\n")
  # First line is envelope header
  let header_line = List.head(lines)
  let header = Json.parse(header_line)?
  let event_id = Json.get(header, "event_id")
  # Process remaining lines as item pairs (header + payload)
  # ... iterate through items, dispatch on type
end
```

### API Key Authentication for Ingestion
```
# Extract API key from request (try multiple methods)
fn extract_api_key(request) -> String!String do
  # Method 1: X-Sentry-Auth header
  case Request.header(request, "x-sentry-auth") do
    Some(auth_header) -> parse_sentry_auth(auth_header)
    None ->
      # Method 2: sentry_key query parameter
      case Request.query(request, "sentry_key") do
        Some(key) -> Ok(key)
        None ->
          # Method 3: Authorization Bearer token (OTLP)
          case Request.header(request, "authorization") do
            Some(bearer) -> parse_bearer_token(bearer)
            None -> Err("no authentication provided")
          end
      end
  end
end

# Validate API key: hash and lookup
fn validate_api_key(pool, key :: String) -> Map<String, String>!String do
  let key_hash = Crypto.sha256(key)
  # Query: SELECT project_id, org_id FROM api_keys
  #   JOIN projects ON projects.id = api_keys.project_id
  #   WHERE key_hash = $1 AND revoked_at IS NULL
  let q = Query.from(ApiKey.__table__())
    |> Query.join_as(:inner, Project.__table__(), "p", "p.id = api_keys.project_id")
    |> Query.where(:key_hash, key_hash)
    |> Query.where_raw("api_keys.revoked_at IS NULL", [])
    |> Query.select_raw(["api_keys.project_id::text", "p.org_id::text"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("invalid API key")
  end
end
```

### Fingerprinting Algorithm
```
# Compute fingerprint from exception type + normalized app frames
# Input: exception_type, stacktrace frames (list of maps)
# Output: SHA-256 hash string

fn compute_fingerprint(exception_type :: String, frames :: List<Map<String, String>>) -> String do
  # 1. Filter to in_app frames only
  let app_frames = List.filter(frames, fn(f) do
    Map.get(f, "in_app") == "true"
  end)

  # 2. Take top 3-5 frames (most recent / closest to error)
  let top_frames = List.take(app_frames, 5)

  # 3. Normalize: filename + function only (strip line numbers)
  let normalized = List.map(top_frames, fn(f) do
    let filename = Map.get(f, "filename")
    let function_name = Map.get(f, "function")
    filename <> ":" <> function_name
  end)

  # 4. Combine and hash
  let fingerprint_input = exception_type <> "|" <> String.join(normalized, "|")
  Crypto.sha256(fingerprint_input)
end
```

### Rate Limiting with Valkey
```
# Sliding window rate limit check
# Key format: "ratelimit:{org_id}:{window_start}"
# Uses INCR + EXPIRE for atomic counter

fn check_rate_limit(valkey_conn, org_id :: String, limit :: Int, window_seconds :: Int) -> Bool do
  let window_key = "ratelimit:" <> org_id <> ":" <> current_window(window_seconds)
  # INCR returns new value atomically
  let count = Valkey.incr(valkey_conn, window_key)
  # Set TTL on first increment
  if count == 1 do
    Valkey.expire(valkey_conn, window_key, window_seconds)
  end
  # Return true if under limit
  count <= limit
end
```

## Database Schema Design

### Events Table (TimescaleDB Hypertable)
```sql
CREATE TABLE events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  issue_id UUID NOT NULL REFERENCES issues(id),
  event_id TEXT NOT NULL,          -- Client-provided event ID (for dedup within SDK)
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  platform TEXT NOT NULL DEFAULT 'unknown',
  level TEXT NOT NULL DEFAULT 'error',       -- error, warning, fatal, info
  message TEXT,                              -- Human-readable message
  exception_type TEXT,                       -- Exception class name
  exception_value TEXT,                      -- Exception message
  stacktrace_json TEXT,                      -- Full normalized stack trace
  environment TEXT NOT NULL DEFAULT 'production',
  release_tag TEXT,                          -- App version/release
  server_name TEXT,                          -- Hostname
  tags_json TEXT DEFAULT '{}',               -- Arbitrary tags
  extra_json TEXT DEFAULT '{}',              -- Arbitrary extra data
  contexts_json TEXT DEFAULT '{}',           -- Runtime/OS/device contexts
  sdk_name TEXT,
  sdk_version TEXT,
  fingerprint TEXT NOT NULL                  -- SHA-256 hash for grouping
);

-- Convert to TimescaleDB hypertable for time-series performance
SELECT create_hypertable('events', 'timestamp');

-- Performance indexes
CREATE INDEX idx_events_project_ts ON events (project_id, timestamp DESC);
CREATE INDEX idx_events_issue ON events (issue_id, timestamp DESC);
CREATE INDEX idx_events_fingerprint ON events (fingerprint);
CREATE INDEX idx_events_environment ON events (project_id, environment);
CREATE INDEX idx_events_level ON events (project_id, level);
```

### Issues Table
```sql
CREATE TABLE issues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  fingerprint TEXT NOT NULL,
  title TEXT NOT NULL,                       -- Exception type: message (truncated)
  level TEXT NOT NULL DEFAULT 'error',
  status TEXT NOT NULL DEFAULT 'open',       -- open, resolved, ignored
  first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_count INT NOT NULL DEFAULT 1,
  environment TEXT,                          -- Primary environment (or NULL for all)
  metadata_json TEXT DEFAULT '{}',           -- Last event sample metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(project_id, fingerprint)
);

CREATE INDEX idx_issues_project_status ON issues (project_id, status);
CREATE INDEX idx_issues_project_last_seen ON issues (project_id, last_seen DESC);
CREATE INDEX idx_issues_fingerprint ON issues (project_id, fingerprint);
```

### Rate Limit Config Table
```sql
CREATE TABLE rate_limit_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE UNIQUE,
  events_per_minute INT NOT NULL DEFAULT 1000,
  burst_limit INT NOT NULL DEFAULT 100,      -- Max events in a single second
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### PII Scrub Rules Table
```sql
CREATE TABLE scrub_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  pattern TEXT NOT NULL,                     -- Regex pattern
  replacement TEXT NOT NULL DEFAULT '[Filtered]',
  description TEXT,                          -- Human-readable rule description
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_scrub_rules_org ON scrub_rules (org_id) WHERE is_active = true;
```

## Protocol Specifications

### Sentry Envelope Format
**Endpoint:** `POST /api/{project_id}/envelope/`
**Content-Type:** `application/x-sentry-envelope` (also accepts `text/plain`)
**Auth:** X-Sentry-Auth header, ?sentry_key query param, or DSN in envelope header
**Response (success):** HTTP 200, `{"id": "<event_id>"}`
**Response (rate limited):** HTTP 429, `Retry-After: <seconds>`, `X-Sentry-Rate-Limits: <retry_after>:<categories>:<scope>:<reason_code>`

**Envelope structure:**
```
{"event_id":"<uuid>","dsn":"https://<key>@<host>/api/<project_id>","sent_at":"2026-03-03T12:00:00Z","sdk":{"name":"sentry.javascript.node","version":"9.x.x"}}\n
{"type":"event","length":<bytes>}\n
<event JSON payload>\n
```

**Event payload (key fields for errors):**
```json
{
  "event_id": "fc6d8c0c43fc4630ad850ee518f1b9d0",
  "timestamp": 1709467200.0,
  "platform": "node",
  "level": "error",
  "environment": "production",
  "release": "my-app@1.0.0",
  "server_name": "web-01",
  "exception": {
    "values": [{
      "type": "TypeError",
      "value": "Cannot read properties of undefined (reading 'map')",
      "stacktrace": {
        "frames": [
          {
            "filename": "app/routes/users.js",
            "function": "getUsers",
            "lineno": 42,
            "colno": 12,
            "abs_path": "/srv/app/routes/users.js",
            "in_app": true
          },
          {
            "filename": "node_modules/express/lib/router/layer.js",
            "function": "Layer.handle",
            "lineno": 95,
            "colno": 5,
            "in_app": false
          }
        ]
      },
      "mechanism": {
        "type": "generic",
        "handled": false
      }
    }]
  },
  "tags": {"browser": "Chrome 120"},
  "extra": {"request_id": "abc123"},
  "contexts": {
    "runtime": {"name": "node", "version": "20.11.0"},
    "os": {"name": "Linux", "version": "6.1.0"}
  }
}
```

### OTLP/HTTP Format
**Endpoints:**
- `POST :4318/v1/logs` -- Error events as log records
- `POST :4318/v1/traces` -- Error events as span events (with exception attributes)
- `POST :4318/v1/metrics` -- Metrics (accept + acknowledge, defer to Phase 4)
**Content-Type:** `application/json` (phase 2 primary), `application/x-protobuf` (defer/spike)
**Auth:** `Authorization: Bearer <api_key>` header
**Response (success):** HTTP 200, `{"partialSuccess":{}}` (JSON) or empty protobuf response
**Response (rate limited):** HTTP 429, `Retry-After: <seconds>`

**OTLP JSON LogRecord structure (error event):**
```json
{
  "resourceLogs": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "my-app"}},
        {"key": "deployment.environment", "value": {"stringValue": "production"}}
      ]
    },
    "scopeLogs": [{
      "scope": {"name": "my-app", "version": "1.0.0"},
      "logRecords": [{
        "timeUnixNano": "1709467200000000000",
        "severityNumber": 17,
        "severityText": "ERROR",
        "body": {"stringValue": "TypeError: Cannot read properties of undefined"},
        "attributes": [
          {"key": "exception.type", "value": {"stringValue": "TypeError"}},
          {"key": "exception.message", "value": {"stringValue": "Cannot read properties of undefined"}},
          {"key": "exception.stacktrace", "value": {"stringValue": "TypeError: Cannot read...\n    at getUsers (app/routes/users.js:42:12)\n    at Layer.handle (node_modules/express/lib/router/layer.js:95:5)"}},
          {"key": "code.filepath", "value": {"stringValue": "app/routes/users.js"}},
          {"key": "code.function", "value": {"stringValue": "getUsers"}},
          {"key": "code.lineno", "value": {"intValue": "42"}}
        ],
        "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
        "spanId": "051581bf3cb55c13"
      }]
    }]
  }]
}
```

**OTLP SeverityNumber mapping:**
| SeverityNumber | Name | Mesher Level |
|---------------|------|-------------|
| 1-4 | TRACE | debug |
| 5-8 | DEBUG | debug |
| 9-12 | INFO | info |
| 13-16 | WARN | warning |
| 17-20 | ERROR | error |
| 21-24 | FATAL | fatal |

### Generic JSON API
**Endpoint:** `POST /api/{project_id}/events`
**Content-Type:** `application/json`
**Auth:** `Authorization: Bearer <api_key>` header
**Response (success):** HTTP 200, `{"id": "<event_id>"}`

**Recommended simplified schema:**
```json
{
  "message": "TypeError: Cannot read properties of undefined",
  "level": "error",
  "environment": "production",
  "exception": {
    "type": "TypeError",
    "value": "Cannot read properties of undefined",
    "stacktrace": [
      {"filename": "app/routes/users.js", "function": "getUsers", "lineno": 42, "in_app": true},
      {"filename": "node_modules/express/lib/router/layer.js", "function": "Layer.handle", "lineno": 95, "in_app": false}
    ]
  },
  "tags": {"browser": "Chrome 120"},
  "extra": {"request_id": "abc123"},
  "release": "1.0.0",
  "server_name": "web-01"
}
```

**Recommendation (Generic API design):** Use a separate `/api/{project_id}/events` endpoint rather than reusing OTLP. The OTLP schema is verbose with nested resource/scope wrappers. A simplified JSON schema is more approachable for custom integrations.

## Discretion Recommendations

### Rate Limiting Scope
**Recommendation:** Per-org rate limiting for Phase 2. The requirement (INGEST-06) says "per-org ingest rate limits." Per-project within an org budget adds complexity. Store the limit config on the org, check it at ingestion time using org_id derived from the API key lookup. Projects share the org's budget.

### Rate Limiting State Storage
**Recommendation:** Valkey-backed. Reasons:
1. Already in the Docker Compose stack (unused since Phase 1)
2. Survives server restarts
3. Atomic INCR operations prevent race conditions
4. Sub-millisecond latency for rate limit checks
5. Works correctly with multiple server instances (future scaling)

In-memory rate limiting would be simpler but fails requirements 2, 3, and 5. Since Valkey is already deployed, using it costs nothing extra operationally.

**Risk:** Mesh Valkey client API is unverified. Needs a spike in the first plan. If Valkey client doesn't work in Mesh, fall back to PostgreSQL advisory locks or in-memory with acknowledgment that it won't scale.

### 429 Response Detail
**Recommendation:** Minimal response body with standard headers. Return:
- HTTP 429 status
- `Retry-After: <seconds>` header (required by both Sentry SDK and OTLP spec)
- `X-Sentry-Rate-Limits: <seconds>:error:org:org_quota` header (for Sentry SDK compatibility)
- Body: `{"error": "rate limit exceeded", "retry_after": <seconds>}`

Do not include usage info (current count, limit) in the response -- this leaks rate limit configuration which could help attackers calibrate their requests.

### Fingerprinting Algorithm Details
**Recommendation for app frame detection (JavaScript):**
- **App frames:** `in_app: true` from the SDK (Sentry provides this). For OTLP, infer from filename: frames with paths containing `node_modules/` are NOT app frames; all others are app frames.
- **Normalization:** For each frame, take `filename` + `function` only. Strip line numbers, column numbers, and absolute path prefixes.
- **Frame selection:** Take the top 3-5 app frames (most recent, closest to the error). "Top" means the end of the frames array in Sentry format (Sentry orders oldest-to-newest, so app frames near the end are closest to the error).
- **Hash input:** `exception_type|frame1_file:frame1_func|frame2_file:frame2_func|...`
- **Hash:** SHA-256 of the concatenated string

This matches the requirement specification exactly: "exception type + normalized top 3-5 application stack frames (line numbers stripped, framework frames excluded)."

### Ingestion Pipeline Topology
**Recommendation:** Synchronous request handling for Phase 2. Mesh's actor model is available but adding actor-based async processing adds complexity that isn't needed until event volume justifies it. The ingestion flow for Phase 2:
1. Receive HTTP request
2. Authenticate (API key lookup -- 1 DB query)
3. Check rate limit (1 Valkey call)
4. Parse protocol (JSON operations)
5. Scrub PII (string operations)
6. Compute fingerprint (string + SHA-256)
7. Upsert issue (1 DB query with ON CONFLICT)
8. Insert event (1 DB query)
9. Return response

Total: ~3 DB queries + 1 Valkey call per event. At the target self-hosted scale, this is fine. Actor-based async processing can be introduced in Phase 5 (real-time push) when events need to be fanned out to WebSocket subscribers.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sentry /store endpoint | Sentry /envelope endpoint | 2020+ | /store is deprecated; all modern SDKs use envelopes |
| OTLP/gRPC primary | OTLP/HTTP (http/protobuf) as default | 2024 | SDK default transport changed to http/protobuf; JSON is the documented fallback |
| Static fingerprinting only | Hybrid fingerprinting + ML embedding | 2024-2025 | Sentry added AI-based grouping (Seer); for Phase 2, deterministic fingerprinting is sufficient |
| Separate exception span events | Migration to log-based exceptions | In progress (2025+) | OTEL_SEMCONV_EXCEPTION_SIGNAL_OPT_IN env var; support both paths |
| Per-category rate limiting | X-Sentry-Rate-Limits with categories | 2021+ | SDKs expect category-aware rate limit headers |

**Deprecated/outdated:**
- Sentry `/api/{project_id}/store/` endpoint: deprecated, use `/envelope/` instead
- OTLP/gRPC as default transport: http/protobuf is now the SDK default
- sentry_secret in X-Sentry-Auth: deprecated, only sentry_key needed

## Open Questions

1. **Mesh Valkey Client API**
   - What we know: Valkey is in the Docker Compose stack, Config.mpl has `valkey_url()`. Phase 1 did not use Valkey.
   - What's unclear: Does Mesh have a Valkey/Redis client in its stdlib? What are the available commands?
   - Recommendation: First plan should include a Valkey connectivity spike. If unavailable, fall back to PostgreSQL-based rate limiting (SELECT ... FOR UPDATE on a counter row) or in-memory counters.

2. **Mesh Protobuf Parsing**
   - What we know: Mesh has JSON parsing and string manipulation. Binary data handling is unverified.
   - What's unclear: Can Mesh read raw bytes from HTTP request bodies? Is there a protobuf library?
   - Recommendation: Start with OTLP/JSON only. Return 415 for protobuf content type. This is spec-compliant. Add protobuf later.

3. **Mesh Regex Support**
   - What we know: Mesh has String.replace, String.starts_with, String.split. PII scrubbing needs regex.
   - What's unclear: Does Mesh stdlib include regex matching? If not, PII scrubbing must use substring-based pattern matching.
   - Recommendation: Check for Regex module in Mesh stdlib during implementation. If unavailable, implement PII scrubbing with substring matching (less precise but functional).

4. **OTLP Port 4318 Separate Listener**
   - What we know: The main HTTP server runs on port 8080. OTLP spec requires port 4318.
   - What's unclear: Can Mesh bind two HTTP listeners on different ports in one process?
   - Recommendation: Try spawning a second HTTP.serve on port 4318. If Mesh doesn't support multiple listeners, use a single port (8080) with path-based routing (/v1/logs, /v1/traces, /v1/metrics) and document port 4318 as configurable via reverse proxy.

5. **TimescaleDB Hypertable Creation in Mesh ORM**
   - What we know: Mesh ORM has Migration.create_table and Pool.execute for raw SQL.
   - What's unclear: Will `SELECT create_hypertable(...)` work via Pool.execute?
   - Recommendation: Use Pool.execute for hypertable creation (same as pgcrypto extension creation in Phase 1). This should work fine.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Mesh test runner (built-in) + curl/httpie integration tests |
| Config file | server/tests/ (to be created) |
| Quick run command | `npm run test:server` |
| Full suite command | `npm run test:server` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INGEST-01 | OTLP/HTTP accepts error LogRecords on port 4318 | integration | curl POST to /v1/logs with JSON payload, verify DB row | No - Wave 0 |
| INGEST-02 | OTLP/HTTP accepts metrics payloads (stub) | integration | curl POST to /v1/metrics, verify 200 response | No - Wave 0 |
| INGEST-03 | Sentry envelope accepted, error stored | integration | curl POST envelope to /api/{pid}/envelope/, verify DB row | No - Wave 0 |
| INGEST-04 | Generic JSON API accepts error events | integration | curl POST to /api/{pid}/events, verify DB row | No - Wave 0 |
| INGEST-05 | API key auth validates on all endpoints | integration | curl with valid/invalid keys, verify 200/403 | No - Wave 0 |
| INGEST-06 | Rate limiting returns 429 with Retry-After | integration | Send N+1 events rapidly, verify 429 on excess | No - Wave 0 |
| INGEST-07 | /health/ingest reports pipeline status | smoke | curl GET /health/ingest, verify JSON response | No - Wave 0 |
| ERR-01 | Events stored with stack trace, message, severity, etc. | integration | POST event, SELECT from events, verify all fields | No - Wave 0 |
| ERR-02 | Events with same fingerprint create one issue | integration | POST 2 identical errors, verify 1 issue with count=2 | No - Wave 0 |
| ERR-10 | Environment tag stored and distinguishable | integration | POST events with different envs, query by env | No - Wave 0 |

### Sampling Rate
- **Per task commit:** Integration test for the specific endpoint being built
- **Per wave merge:** Full curl-based test suite against running server
- **Phase gate:** All 10 requirement tests pass + @sentry/node SDK smoke test

### Wave 0 Gaps
- [ ] `server/tests/` directory -- test infrastructure for integration tests
- [ ] Test helper scripts for starting server, seeding test data (org, project, API key)
- [ ] curl-based integration test scripts for each endpoint
- [ ] @sentry/node SDK compatibility test script (real SDK sending to local server)

## Sources

### Primary (HIGH confidence)
- [Sentry Envelope Specification](https://develop.sentry.dev/sdk/data-model/envelopes/) -- envelope format, item types, authentication
- [Sentry Envelope Items](https://develop.sentry.dev/sdk/data-model/envelope-items/) -- item type specifications
- [Sentry Exception Interface](https://develop.sentry.dev/sdk/data-model/event-payloads/exception/) -- exception payload structure
- [Sentry Stack Trace Interface](https://develop.sentry.dev/sdk/data-model/event-payloads/stacktrace/) -- frame format, in_app detection
- [Sentry Rate Limiting](https://develop.sentry.dev/sdk/expected-features/rate-limiting/) -- X-Sentry-Rate-Limits header format
- [OTLP Specification 1.9.0](https://opentelemetry.io/docs/specs/otlp/) -- OTLP/HTTP protocol, response codes, content types
- [OpenTelemetry Proto (GitHub)](https://github.com/open-telemetry/opentelemetry-proto) -- protobuf message definitions
- [OpenTelemetry Exception Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/exceptions/exceptions-spans/) -- exception.type, exception.message, exception.stacktrace attributes
- [Sentry Grouping Developer Docs](https://develop.sentry.dev/backend/application-domains/grouping/) -- fingerprinting algorithm internals

### Secondary (MEDIUM confidence)
- [Valkey INCR Command](https://valkey.io/commands/incr/) -- rate limiting counter pattern
- [Valkey EXPIRE Command](https://valkey.io/commands/expire/) -- TTL behavior with INCR
- [Redis Rate Limiting Tutorial](https://redis.io/tutorials/howtos/ratelimiting/) -- sliding window implementation (applies to Valkey)
- [Sentry Issue Grouping](https://docs.sentry.io/concepts/data-management/event-grouping/) -- user-facing grouping documentation
- [Sentry Event Payloads](https://develop.sentry.dev/sdk/event-payloads/) -- event attribute reference
- [Datadog PII Scrubbing Rules](https://docs.datadoghq.com/logs/guide/commonly-used-log-processing-rules/) -- common regex patterns for PII
- [OpenTelemetry LogRecord Proto](https://github.com/open-telemetry/opentelemetry-proto/blob/main/opentelemetry/proto/logs/v1/logs.proto) -- severity enum, LogRecord fields

### Tertiary (LOW confidence)
- Mesh Valkey client capabilities -- UNVERIFIED, needs spike
- Mesh regex support -- UNVERIFIED, needs verification
- Mesh multi-port HTTP listener -- UNVERIFIED, needs spike
- Mesh binary/protobuf parsing -- UNVERIFIED, start with JSON

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools are already in the project, proven patterns from Phase 1
- Architecture (common event repr, fingerprinting): HIGH -- well-documented approaches from Sentry/OTLP specs
- Sentry protocol compatibility: MEDIUM-HIGH -- envelope spec is well-documented, but edge cases exist with real SDKs
- OTLP protocol: MEDIUM -- JSON format is clear, protobuf deferred due to Mesh uncertainty
- Rate limiting: MEDIUM -- Valkey patterns are well-known but Mesh Valkey client is unverified
- PII scrubbing: MEDIUM -- patterns are standard but Mesh regex support is unverified
- Pitfalls: HIGH -- well-documented from Sentry developer docs and community

**Research date:** 2026-03-03
**Valid until:** 2026-04-03 (30 days -- protocols are stable, Mesh stdlib may evolve)

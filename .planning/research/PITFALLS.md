# Pitfalls Research

**Domain:** Self-hosted observability platform (Sentry/Datadog alternative)
**Researched:** 2026-03-03
**Confidence:** MEDIUM-HIGH (WebSearch findings verified against multiple authoritative sources)

---

## Critical Pitfalls

### Pitfall 1: Cardinality Explosion in Metrics

**What goes wrong:**
A metric's cardinality is determined by the number of unique label/tag combinations. High-cardinality labels like `user_id`, `tenant_id`, `request_id`, `session_id`, or `container_instance_id` cause an index entry per unique combination. A single metric with three high-cardinality labels can generate millions of unique time series. TimescaleDB's hypertable index, while more efficient than Prometheus, still stores metadata per unique series. At 10 orgs x 50 services x 10 endpoints x 5 envs = 25,000 series for one metric — multiply that by 50 metrics and you have 1.25 million series without any unbounded labels. Introduce a container ID or request ID label and the number becomes astronomical.

**Why it happens:**
Developers instrument first and think about cardinality second. It's natural to add `org_id` or `tenant_id` as a label to "filter by org later." This seems harmless in development with 2 orgs. In production with 500 orgs generating metrics across services, it becomes a storage and query catastrophe.

**How to avoid:**
- Define a strict label allowlist during ingestion. Reject or strip any label that is not in the approved schema.
- Bounded labels only: `env` (3 values), `service` (enumerable), `status_code` (small set). Never `user_id`, `request_id`, `session_id`, or `container_id` as metric labels.
- Store high-cardinality identifiers in the event/span body, not as metric labels.
- Use TimescaleDB continuous aggregates to roll up raw metrics by approved dimensions — query the aggregate, not raw data for dashboards.
- At ingestion: validate label keys against schema. Reject unknown labels with a 400. Log the rejection so clients notice immediately.

**Warning signs:**
- TimescaleDB `timescaledb_catalog.hypertable_chunks` growing faster than expected
- Dashboard queries slowing down week-over-week despite no new feature deployments
- `pg_indexes` sizes growing disproportionately to data volume
- Clients sending metrics with free-form string values as label values

**Phase to address:**
Ingestion pipeline phase. Define the metrics schema (allowed label keys and value constraints) before accepting a single metric. This is a design decision, not a feature — retrofitting it later requires dropping and recreating hypertables.

---

### Pitfall 2: Unbounded Event Storage (Errors Growing Forever)

**What goes wrong:**
Error events are stored in PostgreSQL. Each event has a stack trace, metadata, tags, and breadcrumbs — potentially 10–50KB per event. At 1,000 events/day per organization with 100 orgs, that's 5–50GB/year of raw error data with no lifecycle management. The system feels fast at launch, then silently degrades as table scans slow down, index size bloats, and backup times balloon. Most implementations don't add retention policies until after the first storage crisis.

**Why it happens:**
Events are "just records" — developers think of them like any other data. Unlike metrics (where TimescaleDB's `add_retention_policy` is obvious), error events in a regular PostgreSQL table have no automatic expiry. The need for retention is not visible during development (you have 200 test events), so it's deferred.

**How to avoid:**
- Design the retention model before shipping the first event: default retention period per org (e.g., 90 days), configurable at org level.
- Partition the `events` table by time (or use TimescaleDB and convert it to a hypertable). This makes dropping old data O(1) — dropping a chunk — instead of O(n) DELETE scans.
- Add `add_retention_policy` during initial schema setup, not as a later migration.
- Implement event-level storage quotas per org in addition to time-based retention.
- Separate raw event blobs from indexed metadata: store stack traces in a large-text column or object store; keep searchable fields in indexed columns.

**Warning signs:**
- `events` table growing faster than `pg_stat_user_tables` would suggest from query patterns
- VACUUM taking longer each run
- Autovacuum running constantly on the events table
- Backup duration increasing month-over-month

**Phase to address:**
Schema design phase. The `events` table must be a hypertable from day one. Retention policy configuration belongs in the initial migration, not a future task.

---

### Pitfall 3: schema-per-org Migration Complexity at Scale

**What goes wrong:**
Schema-per-org isolation is implemented early and works well for 5 orgs. Then a schema migration is needed (add a column, create an index). With 500 orgs, this means running the same migration 500 times sequentially, each taking seconds to minutes. Total migration time: hours. During that window, some orgs are on the old schema and some on the new one, requiring code that handles both. A failed migration on org 237 leaves the system in a split-brain schema state that requires manual intervention to resolve.

**Why it happens:**
Multi-tenant schema isolation is designed for data safety, not migration ergonomics. The operational cost of schema-per-org migrations only becomes visible at scale. During development, running 3 migrations on 3 schemas is trivial — the problem is invisible.

**How to avoid:**
- Build a migration orchestrator from day one: a Mesh actor that runs migrations schema-by-schema, tracks success/failure per org, and is idempotent.
- Version every schema with a `schema_version` table inside each org schema. Every migration checks the current version before applying.
- Never run migrations synchronously in application boot. Migrations are background jobs with status tracking.
- Design all schema changes to be backward compatible: add columns as nullable, never rename or drop columns (alias instead). The application must handle both old and new schema during the migration window.
- Test migrations with 50+ org schemas in CI, not just 1.

**Warning signs:**
- Migrations are ad-hoc scripts run manually rather than tracked automation
- No schema version tracking in each org schema
- Migration rollback procedure has never been tested
- All orgs are assumed to be on the same schema version at any point

**Phase to address:**
Multi-tenancy / auth phase. The migration orchestrator must exist before org #2 is onboarded. Retrofitting it after you have 100 orgs is painful.

---

### Pitfall 4: Connection Pool Exhaustion Under schema-per-org

**What goes wrong:**
With schema-per-org, each request must set `search_path` to the correct org schema before querying. With PgBouncer in session pooling mode (the default), a connection stays assigned to the client for the session duration — it cannot be reused by another org's request while active. With 100 concurrent org requests and a pool size of 25, requests queue. With 1000 concurrent requests, the pool is saturated and latencies spike above 10 seconds.

Switching to transaction pooling (which could solve this) breaks `SET search_path` because the setting is session-scoped — after the transaction ends, the connection returns to the pool with the wrong `search_path` for the next user.

**Why it happens:**
The interaction between `search_path` and PgBouncer transaction pooling is non-obvious. The PostgreSQL docs explain it but developers using ORMs or raw PG drivers rarely think about pooling mode during initial development. The problem only surfaces under load.

**How to avoid:**
- Use `SET LOCAL search_path TO [schema], public;` inside every transaction — `SET LOCAL` is transaction-scoped and safe with transaction pooling.
- Configure PgBouncer in transaction pooling mode from the start. Session pooling does not scale.
- Verify with a load test (10 concurrent connections across 20 org schemas) before shipping the ingestion endpoint.
- Set `pool_size` conservatively: PostgreSQL performs best at 25–50 server connections total. More connections = more contention, not more throughput.
- Use a Mesh connection pool actor that manages `search_path` context per request, not per connection.

**Warning signs:**
- PgBouncer pool utilization approaching 100% under moderate load
- `pg_stat_activity` showing many idle-in-transaction sessions
- Timeouts during peak hours but not off-peak
- Application works fine with 1 org in testing but degrades with multiple

**Phase to address:**
Multi-tenancy / auth phase. Connection pool configuration must be validated with a multi-org load test before the ingestion endpoint is considered complete.

---

### Pitfall 5: OTLP Ingestion Without Backpressure

**What goes wrong:**
The OTLP endpoint accepts data as fast as clients send it. Under a traffic spike (e.g., a deployment bug causing 10,000 errors/second), the ingestion endpoint accepts all requests with 200 OK, queues them in memory in the Mesh actor mailbox, the database write rate is overwhelmed, mailboxes fill, memory spikes, and the process crashes or drops events silently. From the client perspective, all requests "succeeded."

**Why it happens:**
HTTP endpoints default to accepting everything. Backpressure is an explicit design decision — you have to build it. Most developers think "I'll add rate limiting later" and later never comes before the first incident.

**How to avoid:**
- Implement ingestion rate limiting per org (e.g., 10,000 events/minute default) from day one. Return `429 Too Many Requests` with a `Retry-After` header.
- Use Mesh actor mailbox bounds: configure max queue depth for ingestion workers. When the mailbox is full, reject with 503 (not silently drop).
- Expose a `/health/ingest` endpoint that returns degraded status when ingestion lag exceeds a threshold. Use this in Docker health checks.
- Implement circuit-breaker logic: if the database write batch fails 3 times, reject new ingestion with 503 until the backlog clears.
- Return `RESOURCE_EXHAUSTED` (HTTP 429) rather than silently dropping — clients can retry with exponential backoff. Silent drops are invisible to operators.

**Warning signs:**
- Ingestion endpoint latency p99 increasing while p50 stays flat (signs of queue buildup)
- Mesh actor mailbox depth metrics climbing during traffic spikes
- Events "accepted" but not appearing in the UI after delays

**Phase to address:**
Ingestion pipeline phase. Backpressure is not a performance optimization — it is a correctness requirement. An ingestion endpoint without backpressure is broken by design.

---

### Pitfall 6: OTLP Version Mismatch and Silent Data Loss

**What goes wrong:**
OTLP is versioned. Clients sending OTLP/HTTP protobuf from SDK version 1.x may use field encodings incompatible with a receiver expecting version 0.x. The request arrives, the receiver parses what it can, silently discards unknown fields, and returns 200 OK. The client believes data was delivered. Operators wonder why certain fields never appear in the UI.

Additionally, clients sending JSON OTLP and receivers expecting protobuf binary (or vice versa) produce parsing errors that may be swallowed rather than surfaced.

**Why it happens:**
OTLP parsers are designed to be forward-compatible (unknown fields ignored). This is intentional for forward-compatibility but makes version mismatches invisible. Developers test with one SDK version and assume all clients behave identically.

**How to avoid:**
- Log the `Content-Type` header for every OTLP request. Alert if you see content types you didn't expect.
- Support both `application/x-protobuf` and `application/json` explicitly and test both.
- Pin the OTLP spec version you support in documentation. When upgrading, run compatibility tests against OTLP test vectors from the OpenTelemetry conformance test suite.
- Add integration tests using actual OTLP SDK clients (not mock HTTP requests) to verify end-to-end field preservation.
- Emit a metric for `otlp_fields_dropped_count` — increment whenever a field is received but not stored. Alert if non-zero.

**Warning signs:**
- Custom attributes set by clients never appear in the UI
- Trace/span IDs arriving malformed or truncated
- Protobuf parse errors in ingestion logs that are being suppressed
- Different SDK versions producing inconsistent event structures

**Phase to address:**
Ingestion pipeline phase. OTLP compatibility testing should be a CI check before the ingestion endpoint ships.

---

### Pitfall 7: Real-Time Dashboard WebSocket Fan-Out Bottleneck

**What goes wrong:**
Each user viewing a live dashboard has a WebSocket connection. As events arrive, the server must push updates to all connected clients viewing that org's data. With 20 users in 10 orgs watching dashboards, that's 200 connections. A single Mesh WebSocket process handling all connections becomes a bottleneck when it must push the same update to 200 sockets sequentially. Under load, the first client gets the update immediately; the 200th client gets it 5 seconds later. The "real-time" dashboard becomes an eventually-consistent dashboard.

**Why it happens:**
WebSocket connections look like HTTP connections during development (small scale, few users). The fan-out problem only emerges when multiple users are connected simultaneously to the same data stream.

**How to avoid:**
- Use a pub/sub model: ingestion actors publish events to named channels (e.g., `org:123:events`). A separate WebSocket gateway actor subscribes to channels and fans out to connected clients.
- The WebSocket gateway should be horizontally scalable — each instance handles a subset of connections. A pub/sub bus (PostgreSQL LISTEN/NOTIFY for low scale, or a dedicated channel in the actor supervisor tree) connects instances.
- Batch updates: don't push every single event. Buffer for 500ms and send a batch. For dashboards this is imperceptible; for ingestion throughput it is critical.
- Cap active WebSocket connections per org to prevent one org from consuming all connection capacity.
- Test with 500 concurrent WebSocket connections before shipping the live dashboard feature.

**Warning signs:**
- Dashboard update latency increases with number of connected users
- WebSocket message queue depth growing under load
- Streem-2 frontend showing "stale" data while new events are visible in other views

**Phase to address:**
Real-time dashboard phase. Fan-out architecture must be designed before the first WebSocket is opened. Retrofitting pub/sub after the dashboard ships requires rewriting the connection management layer.

---

### Pitfall 8: Alert Spam — No Rate Limiting or Cooldown on Notifications

**What goes wrong:**
An alert rule fires when error rate exceeds 1%. A deployment bug causes 1,000 errors/minute for 30 minutes. The alerting system evaluates the rule every 60 seconds, fires 30 times, and sends 30 emails (or webhook calls) to the user. The user, buried under 30 duplicate notifications, ignores all future alerts from this system. Alert fatigue sets in within the first incident. This is the single most common reason teams disable alerting entirely.

**Why it happens:**
Alert rules are easier to build than alert state machines. "If condition is true, send notification" is 5 lines of code. "If condition transitions from false to true, send notification, then suppress for 30 minutes unless condition resolves" requires persistent state and a proper state machine.

**How to avoid:**
- Implement alert state: `inactive → pending → firing → resolved`. Only send notification on `pending → firing` and `firing → resolved` transitions — not on every evaluation.
- Add a `for` duration: the condition must be true for N consecutive evaluations before transitioning to `firing`. This eliminates transient spikes.
- Add re-notification cooldown: if an alert stays in `firing` state, re-notify at most once per configurable period (default: 4 hours).
- Group related alerts: if 5 alert rules fire simultaneously from the same org, batch them into one notification.
- Provide users an easy way to silence an alert for a configurable duration. A silenced alert still fires internally — it just suppresses notifications.

**Warning signs:**
- Users receiving duplicate notifications for the same incident
- Webhook endpoint logs showing the same alert payload every minute
- Users reporting they turned off email notifications entirely
- No concept of "alert state" in the data model — only a log of firings

**Phase to address:**
Alerting phase. Alert state machine must be designed before the first notification is sent. Stateless alerting is not alerting — it is log spam.

---

### Pitfall 9: Error Fingerprinting Producing Too-Broad or Too-Narrow Groups

**What goes wrong:**
Error grouping (deduplication by fingerprint) is the core value of error tracking. Get it wrong in either direction and the feature is useless:

- **Too broad:** All `NullPointerException` events are grouped into one issue regardless of where they occur. A 50,000-count issue hides 5 separate root causes. Users give up trying to triage.
- **Too narrow:** Each error event with a slightly different stack frame (e.g., line number changes after a deploy) creates a new issue. A single bug generates 200 separate issues — one per deploy or one per slightly different call path. The issues list is unmanageable.

**Why it happens:**
Fingerprinting algorithms are opinionated and hard to get right. Sentry spent years tuning theirs. Naive approaches (hash the full stack trace) produce too-narrow grouping; exception-type-only approaches produce too-broad grouping. Most initial implementations choose one extreme and only discover the problem after real traffic reveals the result.

**How to avoid:**
- Fingerprint on: exception type + top N frames of the application code (excluding framework/stdlib frames). N = 3–5 frames is a good starting point.
- Implement frame normalization: strip line numbers, file paths, and memory addresses from frames before fingerprinting. Keep only module path and function name.
- Filter out non-application frames: ignore frames from the HTTP framework, database drivers, and stdlib. Only application frames determine the fingerprint.
- Allow users to override fingerprinting with a custom fingerprint key sent in the event payload (OTLP attribute: `sentry.fingerprint` convention). This is an escape hatch for cases where auto-fingerprinting fails.
- Test fingerprinting with real-world error corpora before shipping. Sentry's test corpus is publicly available.

**Warning signs:**
- Issues with event counts > 100,000 where the issue detail reveals multiple distinct error locations
- Many issues with event count = 1 (or very low) that look identical to human reviewers
- Users manually merging or splitting issues constantly

**Phase to address:**
Error tracking core phase. Fingerprinting logic must be validated before the issues list UI is built. You cannot retrofit good fingerprinting after issues have been grouped incorrectly — existing data requires re-processing.

---

### Pitfall 10: Beta Toolchain Risk — Tool Limitations Discovered Late

**What goes wrong:**
Mesh, Streem-2, and LitUI are beta tools. Beta tools have missing features, APIs that change between versions, and bugs that can only be discovered by building with them. If a critical Mesh limitation (e.g., WebSocket actor supervision model doesn't support fan-out patterns) is discovered in Phase 5 after 4 phases of implementation, the entire real-time layer may need to be rearchitected. Similarly, if a LitUI charting component lacks a feature needed for the heatmap dashboard (discovered in Phase 6), Phase 6 blocks until the tool is patched.

**Why it happens:**
Beta tools feel like mature tools during demos and initial scaffolding. The limitations appear at integration boundaries: when you combine two features, when you push scale limits, or when you hit edge cases in the API. Developers defer integration risk by building components in isolation — the risky interactions are only discovered when components are wired together.

**How to avoid:**
- **Spike each critical beta tool capability in Phase 1** before any production code is written. Specifically:
  - Mesh: WebSocket actor supervision, actor mailbox backpressure, PostgreSQL transaction pooling with dynamic `search_path`
  - Streem-2: WebSocket stream adapter reconnection behavior, SSE adapter under connection drop, signal propagation performance with high-frequency updates
  - LitUI: heatmap chart with live-updating data, data-table with 10,000+ rows, date-picker range selection behavior
- Maintain a "Tool Limitations Log" document updated whenever a limitation is found. Each entry must include: tool, version, limitation, workaround (if any), or escalation status.
- Structure early phases as integration validators, not just feature deliverers. The goal of Phase 1 is not only to ship scaffolding — it is to prove the toolchain can deliver what Phase 3–6 requires.
- Never accumulate unverified assumptions about beta tool capabilities across multiple phases. An assumption that turns out to be wrong late in the roadmap is a rewrite, not a bug fix.

**Warning signs:**
- Phase 1 completes with no Mesh/Streem-2/LitUI edge cases encountered (likely means edge cases weren't tested)
- Developer is building features that will depend on untested tool capabilities
- No escalation has ever occurred (either the tools are perfect, or limitations aren't being surfaced)

**Phase to address:**
Phase 1 (project scaffolding / spike). Every critical capability of every beta tool must be exercised in the first phase before feature development begins. This is the single highest-leverage risk reduction activity for this project.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Regular PG table for events (not hypertable) | Simpler initial migration | Retention requires full DELETE scans; no compression; no chunk pruning | Never — convert to hypertable in Phase 1 |
| Hardcoded retention of "never delete" | No retention logic to write | Storage grows unbounded; first prod incident is a disk-full at 3 AM | Never |
| Stateless alerting (fire every evaluation) | Simpler alert engine | Alert spam kills user trust within the first real incident | Never |
| Session pooling in PgBouncer | No `SET LOCAL` complexity | Pool saturates at 25–50 concurrent org requests | Only for local dev; switch to transaction pooling before first load test |
| Wide-open OTLP label ingestion | Accept any client data | Cardinality explosion from one misconfigured client | Never — enforce label schema at ingestion from day one |
| Sync migrations at app boot | Simple deployment | Boot fails if any org migration fails; 500-org migrations block startup for hours | Never — use async migration worker |
| Single WebSocket actor for all connections | Simple to implement | Fan-out bottleneck at >50 concurrent dashboard users | Only for Phase 1 spike; replace before real-time dashboard ships |
| Fingerprint = hash(full stack trace) | Trivial to implement | Every deploy creates new issues; issues list becomes unmanageable | Only for prototype; replace before shipping issues list to users |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| OTLP/HTTP ingestion | Accepting both protobuf and JSON but only testing one | Test both content types in CI with actual SDK clients |
| TimescaleDB hypertables | Running `create_hypertable` on a table that already has data | Create hypertable during initial migration before any data is inserted |
| TimescaleDB continuous aggregates + retention | Setting retention policy on raw table without refreshing aggregates first | Refresh aggregates before raw data drops; configure `add_retention_policy` on the aggregate separately |
| PgBouncer + schema-per-org | Using `SET search_path` without `LOCAL` in transaction pooling mode | Always use `SET LOCAL search_path TO [schema], public;` inside every transaction |
| Streem-2 WebSocket adapter | Not handling reconnection events — UI shows stale data silently after disconnect | Subscribe to connection state signal; show "reconnecting..." UI; replay last known state on reconnect |
| LitUI chart components | Updating chart data on every WebSocket message (causes render thrash) | Batch updates with a 500ms debounce; update once per tick, not per event |
| OTLP protobuf parsing | Using a generic protobuf library rather than OTLP-specific generated types | Use the official OTLP proto definitions; do not hand-roll the parser |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| No time-range index on events table | Dashboard queries scanning full table | Composite index on `(org_id, occurred_at DESC)` from day one | At ~100K events per org |
| Querying raw metrics instead of continuous aggregates | Dashboard p99 latency > 5s for 30-day views | Build continuous aggregates for all standard time windows (1h, 24h, 7d, 30d) | At ~1M metric data points |
| SELECT * in issues list with full event payloads | Issues list load time > 3s | Select only indexed columns for list view; fetch full event payload on demand | At ~10K issues per org |
| Synchronous event processing in HTTP handler | Ingestion endpoint p99 increases under load | Hand off to Mesh actor mailbox immediately; return 202 Accepted | At ~100 events/second per process |
| WebSocket pushing every individual event | Frontend render loop thrash; high CPU | Batch events into 500ms windows before push | At ~10 events/second per dashboard |
| Schema migration blocking all requests | Timeouts during deployments | Use non-blocking DDL: `ADD COLUMN ... DEFAULT NULL` never locks; multi-step approach for others | First time a large-org migration runs |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Missing `org_id` filter in any query | Cross-tenant data leakage — one org reads another's errors | Every query MUST include `org_id` filter; automated test that attempts cross-tenant access and asserts empty result |
| API keys not scoped to org | A leaked SDK key allows sending events to any org | API keys are always scoped: `(key_hash, org_id)` — validate both on every request |
| PII in error payloads stored without scrubbing | GDPR violations; exposure of user data in error UI | Implement configurable PII scrubber at ingestion; regex patterns for common PII (email, IP, credit card); on by default |
| Webhook URLs stored in plaintext | Leaked DB backup exposes webhook targets | Encrypt webhook URLs at rest; decrypt only when firing notification |
| No rate limit on public ingestion endpoint | DoS from a misconfigured or malicious SDK | Per-org rate limiting on all ingestion endpoints from day one; IP-level rate limiting on the endpoint itself |
| Auth token included in error event breadcrumbs | SDK auto-captures HTTP headers including Authorization | Header scrubbing: strip Authorization, Cookie, X-API-Key from captured HTTP breadcrumbs by default |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No "first seen / last seen" timestamps on issues | Users cannot triage by recency or understand incident duration | Show both timestamps prominently; add "new issue" badge for issues first seen in last 24h |
| Showing raw event count instead of affected-period context | 50,000 events means nothing without time context | Show "50K events in last 7 days" with a sparkline trend chart |
| Alert notifications with no context | Engineer receives "error rate exceeded threshold" at 3 AM with no link or data | Alert notifications must include: metric value, threshold, time window, link to dashboard, and top offending service |
| Issues list with no status indicators | Users cannot see which issues are being worked on | Open/resolved/ignored/regressed status with color coding; bulk status actions |
| Dashboard with no loading state for slow queries | User thinks dashboard is broken; refreshes repeatedly (worsening the query load) | Skeleton loading states for every chart; cancel in-flight queries when user navigates away |
| Live updates that interrupt user interaction | User is typing a search query; data refresh resets the input | Pause live updates when user is interacting with a form or filter; resume on blur |
| No empty states | A new project with no events shows blank charts — user thinks setup failed | Explicit "no data yet" state with setup instructions; "send a test event" button |

---

## "Looks Done But Isn't" Checklist

- [ ] **Error ingestion:** Often missing — what happens when the DB is down? Verify: ingestion returns 503 (not 200) and no data is silently dropped
- [ ] **Issue deduplication:** Often missing — has the fingerprinting algorithm been tested with real error corpora across multiple deploy versions? Verify: run 1000 real errors through it and manually inspect groupings
- [ ] **Alerting:** Often missing — alert state machine with `pending → firing → resolved` transitions. Verify: an alert that fires and then recovers sends exactly 2 notifications (firing + resolved), not one per evaluation
- [ ] **Schema migrations:** Often missing — migration idempotency and rollback. Verify: run the same migration twice; second run must succeed (no-op) without error
- [ ] **Retention policy:** Often missing — test that retention actually deletes data. Verify: insert data with old timestamps; run retention job; data is gone
- [ ] **Cross-tenant isolation:** Often missing — automated test that uses Org A's API key to request Org B's data and asserts empty result (not an error, not Org B's data)
- [ ] **Backpressure:** Often missing — verify the ingestion endpoint returns 429 when overwhelmed, not 200 with silent drops. Test by sending 10x rate limit in a burst.
- [ ] **WebSocket reconnection:** Often missing — kill the WebSocket server mid-connection; verify the Streem-2 frontend reconnects and the dashboard returns to live state within 10 seconds

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Cardinality explosion already in production | HIGH | Drop affected hypertable; redesign label schema; re-ingest from source (may be impossible); add label schema enforcement going forward |
| Unbounded event storage (disk full) | MEDIUM | Emergency retention job to delete oldest events; add hypertable partitioning; downtime likely |
| Migration state corruption (half-migrated orgs) | HIGH | Audit each org schema version; manually apply missing migrations; test each org after repair; 1–4 hours per 100 orgs |
| Alert spam already eroded user trust | MEDIUM | Silence all alerts; communicate the fix; re-enable with proper state machine; trust rebuilds slowly |
| Fingerprinting produced wrong groups | HIGH | Re-process all historical events through new fingerprinting algorithm; merge/split issues in the DB; notify users of issue ID changes |
| PgBouncer pool exhaustion in production | LOW-MEDIUM | Switch PgBouncer to transaction mode; update all queries to use `SET LOCAL`; rolling deployment with load test validation |
| Beta tool limitation discovered in Phase 4 | HIGH | Work stops; escalate to developer; timeline blocked until patch; no workarounds permitted |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Cardinality explosion | Ingestion pipeline phase | Send a metric with 1000 unique label values; verify it is rejected or stripped |
| Unbounded event storage | Schema design phase (Phase 1) | Insert 10K events; verify retention job deletes events older than configured period |
| schema-per-org migration complexity | Multi-tenancy / auth phase | Run a migration against 50 test org schemas; verify idempotency and rollback |
| Connection pool exhaustion | Multi-tenancy / auth phase | Load test with 100 concurrent requests across 20 orgs; verify p99 < 500ms |
| OTLP ingestion without backpressure | Ingestion pipeline phase | Send 100x rate limit in burst; verify 429 responses and no silent drops |
| OTLP version mismatch | Ingestion pipeline phase | Run OTLP conformance tests with SDK clients; verify all standard fields are stored |
| WebSocket fan-out bottleneck | Real-time dashboard phase | Connect 200 WebSocket clients; verify all receive updates within 1s of ingestion |
| Alert spam | Alerting phase | Trigger an alert; let it fire for 5 evaluations; verify exactly 1 notification sent |
| Poor error fingerprinting | Error tracking core phase | Run 1000 real errors through fingerprinter; inspect groupings for obvious splits/merges |
| Beta toolchain limitations | Phase 1 spike | Every critical capability of each tool has a passing integration test |

---

## Sources

- [The high-cardinality trap: why your observability platform is failing — ClickHouse Engineering](https://clickhouse.com/resources/engineering/high-cardinality-slow-observability-challenge) (MEDIUM confidence — authoritative vendor engineering blog)
- [Metric Cardinality in Observability Platforms — Netdata Academy](https://www.netdata.cloud/academy/metric-cardinality-in-observability/) (MEDIUM confidence)
- [Designing a Modern Observability Platform: Principles, Patterns & Pitfalls — Nerd Level Tech](https://nerdleveltech.com/designing-a-modern-observability-platform-principles-patterns-pitfalls) (MEDIUM confidence)
- [A Deep Dive into the OpenTelemetry Protocol (OTLP) — Better Stack Community](https://betterstack.com/community/guides/observability/otlp/) (MEDIUM confidence — well-researched community guide)
- [How to Implement Backpressure Handling in OpenTelemetry Pipelines — OneUptime](https://oneuptime.com/blog/post/2026-02-06-backpressure-handling-opentelemetry-pipelines/view) (MEDIUM confidence)
- [Handling Load and Backpressure — Datadog Observability Pipelines Docs](https://docs.datadoghq.com/observability_pipelines/scaling_and_performance/handling_load_and_backpressure/) (HIGH confidence — official vendor docs)
- [I gave up on self-hosted Sentry (2024) — Hacker News Discussion](https://news.ycombinator.com/item?id=43725815) (MEDIUM confidence — community experience)
- [Self-Hosted Sentry — Sentry Developer Docs](https://develop.sentry.dev/self-hosted/) (HIGH confidence — official docs)
- [PgBouncer at Scale: 10K+ Connections Multi-Tenant Postgres — DZone](https://dzone.com/articles/database-connection-pooling-at-scale-pgbouncer-mul) (MEDIUM confidence)
- [Designing Your Postgres Database for Multi-tenancy — Crunchy Data Blog](https://www.crunchydata.com/blog/designing-your-postgres-database-for-multi-tenancy) (HIGH confidence — Crunchy Data is a PostgreSQL authority)
- [TimescaleDB Guide — TechPrescient](https://www.techprescient.com/blogs/timescaledb/) (MEDIUM confidence)
- [How to Configure Data Retention Policies in TimescaleDB — OneUptime](https://oneuptime.com/blog/post/2026-02-02-timescaledb-data-retention/view) (MEDIUM confidence)
- [Alerting Best Practices — VictoriaMetrics Blog](https://victoriametrics.com/blog/alerting-best-practices/) (MEDIUM confidence — VictoriaMetrics is a serious observability vendor)
- [Grafana Alerting best practices — Grafana Official Docs](https://grafana.com/docs/grafana/latest/alerting/guides/best-practices/) (HIGH confidence — official docs)
- [Tenant Isolation in Multi-Tenant Systems — Security Boulevard](https://securityboulevard.com/2025/12/tenant-isolation-in-multi-tenant-systems-architecture-identity-and-security/) (MEDIUM confidence)
- [10 WebSocket Scaling Patterns for Real-Time Dashboards — Medium/Syntal](https://medium.com/@sparknp1/10-websocket-scaling-patterns-for-real-time-dashboards-1e9dc4681741) (LOW confidence — single community source)
- [Postgres Multi-tenancy RLS vs Schemas vs Separate DBs — Debugg AI](https://debugg.ai/resources/postgres-multitenancy-rls-vs-schemas-vs-separate-dbs-performance-isolation-migration-playbook-2025) (MEDIUM confidence)

---

*Pitfalls research for: Mesher — self-hosted observability platform*
*Researched: 2026-03-03*

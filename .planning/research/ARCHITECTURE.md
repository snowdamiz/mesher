# Architecture Research

**Domain:** Self-hosted observability platform (errors + metrics + alerting)
**Researched:** 2026-03-03
**Confidence:** HIGH (patterns verified against SigNoz official docs, OpenTelemetry official docs, Sentry dev docs, TimescaleDB docs, multiple corroborating sources)

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         INGESTION LAYER                               │
│                                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │
│  │ OTLP HTTP   │  │ Mesh SDK    │  │ Generic HTTP │                   │
│  │ :4318       │  │ (actor SDK) │  │ API          │                   │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                   │
│         └────────────────┴────────────────┘                          │
│                          │                                            │
│                ┌──────────▼──────────┐                                │
│                │  IngestionActor     │                                │
│                │  (fan-out, buffer,  │                                │
│                │   validate, route)  │                                │
│                └──────────┬──────────┘                                │
│           ┌───────────────┼───────────────┐                          │
│           │               │               │                          │
│  ┌────────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐                  │
│  │ ErrorIngest   │ │MetricIngest │ │ BatchWriter │                   │
│  │ Actor         │ │ Actor       │ │ Actor       │                   │
│  │ (fingerprint, │ │ (normalize, │ │ (bulk flush)│                   │
│  │  group, dedup)│ │  downsample)│ └─────────────┘                   │
│  └───────────────┘ └─────────────┘                                   │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         STORAGE LAYER                                 │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  PostgreSQL (per-org schemas)                                │     │
│  │                                                              │     │
│  │  schema: org_{id}                                            │     │
│  │  ├── errors          (event table)                           │     │
│  │  ├── issues          (grouped errors)                        │     │
│  │  ├── metrics         (TimescaleDB hypertable)                │     │
│  │  ├── metrics_1m      (continuous aggregate — 1 min)          │     │
│  │  ├── metrics_1h      (continuous aggregate — 1 hr)           │     │
│  │  └── alert_rules     (threshold definitions)                 │     │
│  │                                                              │     │
│  │  schema: public (global)                                     │     │
│  │  ├── organizations                                           │     │
│  │  ├── users                                                   │     │
│  │  ├── projects                                                │     │
│  │  └── api_keys                                                │     │
│  └─────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         QUERY LAYER                                   │
│                                                                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐       │
│  │ QueryActor      │  │ AlertEval       │  │ NotifActor      │       │
│  │ (REST API +     │  │ Actor           │  │ (email,         │       │
│  │  WebSocket sub) │  │ (periodic eval) │  │  webhook)       │       │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘       │
└──────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       PRESENTATION LAYER                              │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │  Streem-2 Frontend (SSR'd or SPA)                            │     │
│  │  ├── Dashboard views (LitUI charts)                          │     │
│  │  ├── Error / Issue views (LitUI data-table)                  │     │
│  │  ├── Alert management                                        │     │
│  │  └── fromWebSocket() / fromSSE() live data adapters          │     │
│  └─────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Component Responsibilities

| Component | Responsibility | Mesh Implementation |
|-----------|----------------|---------------------|
| **IngestionActor** | Receive raw OTLP/HTTP events, validate envelope, fan-out to typed ingest actors | Mesh actor; owns HTTP + WebSocket listeners on ingest port |
| **ErrorIngestActor** | Fingerprint errors, deduplicate against existing issues, write to `errors` + update `issues` | Mesh actor; stateless logic, supervised by IngestionSupervisor |
| **MetricIngestActor** | Normalize metric data points, batch-write to TimescaleDB hypertables | Mesh actor; maintains small in-memory batch buffer |
| **BatchWriterActor** | Coalesce high-volume writes into bulk inserts, flush on size or timer | Mesh actor; owns PG connection pool |
| **QueryActor** | Handle REST API requests + manage WebSocket subscriptions per org | Mesh actor; routes queries to correct org schema |
| **AlertEvalActor** | Periodically (configurable interval) evaluate alert rules, emit firing/resolved events | Mesh actor with internal timer loop |
| **NotifActor** | Receive alert events, dispatch to email/webhook channels, deduplicate notifications | Mesh actor; stateless delivery |
| **AuthActor** | Validate API keys and session tokens, enforce org/project scoping on every request | Mesh actor; in-process caching of verified tokens |
| **PostgreSQL + TimescaleDB** | Primary data store; org schema isolation; hypertables for metrics; continuous aggregates for rollup queries | Mesh built-in PG driver; TimescaleDB as PG extension |
| **Streem-2 Frontend** | Reactive UI with signal-driven live data; `fromWebSocket()` adapter streams metric updates | No server needed beyond Mesh HTTP static serving |

---

## Recommended Project Structure

```
mesher/
├── backend/
│   ├── actors/
│   │   ├── ingestion/
│   │   │   ├── ingestion_actor.mesh      # Fan-out entrypoint
│   │   │   ├── error_ingest_actor.mesh   # Fingerprint + group
│   │   │   └── metric_ingest_actor.mesh  # Normalize + batch
│   │   ├── query/
│   │   │   ├── query_actor.mesh          # REST + WS subscriptions
│   │   │   └── subscription_manager.mesh # Per-org WS channel registry
│   │   ├── alerting/
│   │   │   ├── alert_eval_actor.mesh     # Evaluation loop
│   │   │   └── notif_actor.mesh          # Delivery
│   │   └── auth/
│   │       └── auth_actor.mesh           # Token validation
│   ├── db/
│   │   ├── migrations/
│   │   │   ├── global/                   # public schema migrations
│   │   │   └── tenant/                   # per-org schema template
│   │   └── queries/
│   │       ├── errors.mesh               # Error/issue query helpers
│   │       └── metrics.mesh              # TimescaleDB query helpers
│   ├── domain/
│   │   ├── fingerprint.mesh              # Error grouping algorithm
│   │   ├── otlp.mesh                     # OTLP envelope parsing
│   │   └── tenant.mesh                   # Schema routing helpers
│   └── main.mesh                         # Supervisor tree root
├── frontend/
│   ├── src/
│   │   ├── pages/
│   │   │   ├── dashboard/                # Metrics dashboard
│   │   │   ├── errors/                   # Error list + detail
│   │   │   ├── alerts/                   # Alert rule management
│   │   │   └── settings/                 # Org / API keys / projects
│   │   ├── streams/
│   │   │   ├── metrics_stream.ts         # fromWebSocket() adapter
│   │   │   └── events_stream.ts          # fromSSE() adapter
│   │   └── main.ts                       # Streem-2 app entrypoint
├── deploy/
│   ├── docker-compose.yml                # Self-hosted one-command
│   └── helm/                             # Kubernetes chart
└── sdk/
    └── mesh/                             # Mesh native SDK
        └── mesher_sdk.mesh               # Actor crash reporter + HTTP middleware
```

### Structure Rationale

- **`actors/`**: Each actor maps directly to a bounded concern; changes to one actor don't require touching others. Actors are the unit of supervision and restart.
- **`db/migrations/global/` vs `db/migrations/tenant/`**: Global migrations run once at startup; tenant migrations run as a template when a new org is provisioned — critical for schema-per-org isolation.
- **`domain/`**: Pure business logic (fingerprinting, OTLP parsing) with no actor dependencies; unit-testable without spawning actors.
- **`streams/`**: Streem-2 stream adapters are isolated so UI components can consume live data without knowing the underlying transport.
- **`sdk/`**: Separate from backend so it can be versioned and published independently.

---

## Architectural Patterns

### Pattern 1: Actor-Per-Concern Ingestion with Supervisor Trees

**What:** Each stage of the ingestion pipeline is its own Mesh actor with a dedicated supervisor. The `IngestionSupervisor` owns `IngestionActor`, `ErrorIngestActor`, `MetricIngestActor`, and `BatchWriterActor`. If `MetricIngestActor` crashes (e.g., a malformed metric payload), only that actor restarts — ingestion of errors continues uninterrupted.

**When to use:** Any stateful or failure-prone processing stage. Actor isolation means a bad payload cannot take down the whole ingestion pipeline.

**Trade-offs:**
- Pro: Fault isolation, natural backpressure via mailbox depth
- Con: Message-passing overhead (negligible at observability volume; BEAM-style systems handle millions of messages/sec)

**Example structure:**
```
IngestionSupervisor (one_for_one)
  └── IngestionActor          ← HTTP listener + fan-out
  └── ErrorIngestActor        ← fingerprint + dedup
  └── MetricIngestActor       ← normalize + batch buffer
  └── BatchWriterActor        ← bulk flush to PG
```

### Pattern 2: Schema-Per-Org Routing via Connection Context

**What:** Every database query includes a `SET search_path = org_{id}` call (or equivalent Mesh PG driver call) before executing. The `QueryActor` extracts `org_id` from the validated API key and passes it as context to all DB helpers. No shared table for telemetry data — each org's errors/metrics live in their own schema.

**When to use:** Multi-tenant platforms where data leakage between orgs is a hard requirement and the expected org count is under a few thousand (schema-per-org scales well to ~2,000 orgs, degrades at 10,000+).

**Trade-offs:**
- Pro: Impossible to accidentally query across org boundaries; schema drift per org is possible for advanced customization
- Con: New tenant provisioning requires schema creation + running migration template; cross-org aggregate analytics requires joining across schemas (not needed for Mesher's feature set)

**Example query pattern:**
```
// Set org context before any query
db.execute("SET search_path TO org_${org_id}, public")
// Now all table references resolve to org-scoped tables
db.query("SELECT * FROM errors WHERE project_id = $1", [project_id])
```

### Pattern 3: TimescaleDB Continuous Aggregates for Dashboard Performance

**What:** Raw metrics are written to a TimescaleDB hypertable (`metrics`). Continuous aggregates at 1-minute and 1-hour granularity are defined as materialized views that refresh automatically in the background. Dashboard queries hit the aggregate, not the raw hypertable.

**When to use:** Any metrics dashboard with configurable time windows (last 1h, 24h, 7d, 30d). Raw hypertable queries for 7-day ranges are 10–100x slower than pre-aggregated queries.

**Trade-offs:**
- Pro: Dashboard query latency drops from seconds to milliseconds; real-time mode (TimescaleDB feature) adds the most recent raw rows to aggregate results so dashboards stay current
- Con: Background refresh adds slight write amplification; aggregate definitions must be planned ahead and are harder to backfill if schema changes

**Example schema:**
```sql
-- Raw hypertable (per org schema)
CREATE TABLE metrics (
  time        TIMESTAMPTZ NOT NULL,
  project_id  UUID        NOT NULL,
  name        TEXT        NOT NULL,
  value       DOUBLE PRECISION,
  tags        JSONB
);
SELECT create_hypertable('metrics', 'time');

-- 1-minute continuous aggregate
CREATE MATERIALIZED VIEW metrics_1m
WITH (timescaledb.continuous) AS
  SELECT time_bucket('1 minute', time) AS bucket,
         project_id, name,
         avg(value) AS avg_val,
         min(value) AS min_val,
         max(value) AS max_val
  FROM metrics
  GROUP BY bucket, project_id, name;
```

### Pattern 4: WebSocket Channel Registry for Real-Time Push

**What:** `QueryActor` maintains an in-memory registry mapping `org_id → [ws_connection_ids]`. When `MetricIngestActor` writes new data, it sends an internal actor message to `QueryActor` ("new data for org X"). `QueryActor` looks up active WS connections for that org and pushes a delta payload. On the frontend, `fromWebSocket()` in Streem-2 drives reactive signals that update charts without a page reload.

**When to use:** Metric dashboards that need sub-second updates without polling. SSE is simpler (HTTP/2 native, auto-reconnect) and sufficient for metrics push (server → client only). WebSocket adds bidirectional control (e.g., client can send filter changes while subscribed).

**Trade-offs:**
- Pro: Zero-polling, genuine push; Streem-2's `fromWebSocket()` integrates natively
- Con: Server must track open connections (stateful); need sticky sessions or connection tracking if multiple Mesh instances run behind load balancer

**Connection lifecycle:**
```
Client opens WS → QueryActor registers connection for org_id
Ingestion writes new metric → sends msg to QueryActor
QueryActor → pushes delta to all registered connections for that org
Client disconnects → QueryActor removes from registry
```

---

## Data Flow

### Full Ingestion → Storage → Query → UI Flow

```
SDK / OTLP client
    │
    │  HTTP POST /v1/ingest (OTLP protobuf or JSON)
    │  Header: Authorization: Bearer <api_key>
    ▼
AuthActor  ──── validates API key ────► resolves org_id + project_id
    │
    ▼
IngestionActor
    │  validates envelope structure
    │  fan-outs to typed actor
    │
    ├──► ErrorIngestActor
    │        │  compute SHA1 fingerprint (type + normalized frames)
    │        │  check issues table for existing fingerprint
    │        │  INSERT into errors; UPDATE or INSERT issues
    │        └──► BatchWriterActor (bulk flush)
    │
    └──► MetricIngestActor
             │  normalize data points (name, tags, timestamp, value)
             │  append to in-memory batch
             │  on flush: INSERT INTO metrics (TimescaleDB hypertable)
             │  notify QueryActor: "org X has new metric data"
             └──► QueryActor subscription dispatch

QueryActor
    │  receives "new data for org X"
    │  looks up active WS connections for org X
    └──► sends delta payload to each registered WS connection

Browser (Streem-2 frontend)
    │  fromWebSocket() adapter receives push frame
    │  signal() updates chart data
    └──► LitUI chart re-renders reactively (no page reload)
```

### Alert Evaluation Flow

```
AlertEvalActor (timer loop, configurable interval e.g. 1 min)
    │
    │  for each org: load active alert rules from DB
    │  execute rule query against metrics_1m or metrics_1h
    │  compare result against threshold
    │
    ├── if FIRING: send msg to NotifActor
    │       │  NotifActor checks last-fired timestamp (dedup window)
    │       │  if outside dedup window: dispatch email / webhook
    │       └──► QueryActor: push alert event to org's WS connections
    │
    └── if RESOLVED: send resolve msg to NotifActor
            └──► dispatch resolved notification
```

### REST Query Flow

```
Browser → GET /api/v1/metrics?project=X&window=1h&metric=cpu
    ↓
QueryActor
    ├── validates session token (AuthActor)
    ├── SET search_path = org_{id}
    ├── SELECT FROM metrics_1m WHERE project_id = X AND ...
    └── returns JSON response

Browser → GET /api/v1/issues?project=X&status=open
    ↓
QueryActor
    ├── validates session token
    ├── SET search_path = org_{id}
    ├── SELECT FROM issues JOIN errors ...
    └── returns paginated JSON
```

---

## Mesh Actor Mapping

The following table maps each system concern to the Mesh actor that owns it. This is the authoritative guide for build order and dependency tracing.

| Actor | Type | Owns | Dependencies |
|-------|------|------|--------------|
| `IngestionSupervisor` | Supervisor | Restart strategy for all ingest actors | None (root) |
| `IngestionActor` | Worker | HTTP + OTLP listener, envelope validation, fan-out | AuthActor, ErrorIngestActor, MetricIngestActor |
| `ErrorIngestActor` | Worker | Fingerprinting, deduplication, issue grouping | BatchWriterActor, PG (org schema) |
| `MetricIngestActor` | Worker | Metric normalization, batch buffer | BatchWriterActor, QueryActor (notify) |
| `BatchWriterActor` | Worker | Bulk PG writes, flush timer | PG connection |
| `QueryActor` | Worker | REST API handler, WS connection registry, subscription dispatch | PG (org schema) |
| `AlertEvalActor` | Worker | Periodic rule evaluation, firing/resolved events | PG (metrics_1m, alert_rules), NotifActor, QueryActor |
| `NotifActor` | Worker | Email + webhook delivery, dedup window | External SMTP / HTTP |
| `AuthActor` | Worker | API key and session token validation, org resolution | PG (public.api_keys, public.sessions) |
| `TenantProvisionActor` | Worker | Create org schema, run tenant migrations on new org signup | PG |

---

## Build Order (Critical Path)

Build order is dictated by hard runtime dependencies: an actor cannot be started until its dependencies exist.

```
Phase 1: Foundation
  ├── Database schema (global: orgs, users, api_keys, projects)
  ├── AuthActor (all other actors need auth)
  └── TenantProvisionActor (org signup must work before any data can be stored)

Phase 2: Ingestion Core
  ├── BatchWriterActor (depends on: PG connection, org schema template)
  ├── ErrorIngestActor (depends on: BatchWriterActor)
  ├── MetricIngestActor (depends on: BatchWriterActor)
  └── IngestionActor (depends on: Auth, Error, Metric ingest actors)

Phase 3: Query + REST API
  └── QueryActor (depends on: AuthActor, PG org schemas with data)

Phase 4: Real-Time Push
  └── WebSocket subscription layer in QueryActor (depends on: QueryActor, MetricIngestActor notify)

Phase 5: Alerting
  ├── AlertEvalActor (depends on: QueryActor/PG metrics data, NotifActor)
  └── NotifActor (no hard dependencies; needs SMTP/webhook config)

Phase 6: Frontend
  └── Streem-2 UI (depends on: QueryActor REST API + WS endpoints being live)

Phase 7: SDK
  └── Mesh native SDK (depends on: IngestionActor HTTP API being stable)

Phase 8: Deployment
  └── Docker Compose + Kubernetes Helm (depends on: all above being production-ready)
```

**Why this order matters:**
- Phases 1–3 are the minimum viable loop: you can ingest data and query it back.
- Phase 4 (real-time push) requires Phase 3 to exist; the WS registry lives inside QueryActor.
- Phase 5 (alerting) depends on metric data already accumulating in the DB (Phase 2).
- Phase 6 (frontend) can be developed in parallel after Phase 3 REST API stabilizes, but integration requires Phases 1–4.
- Phase 7 (SDK) is a developer experience layer; the HTTP API it calls must be stable first.

---

## Multi-Tenancy: How Schema-Per-Org Affects Architecture

### Provisioning Flow

```
New org signs up
    ↓
TenantProvisionActor
    ├── INSERT INTO public.organizations (id, name, ...)
    ├── CREATE SCHEMA org_{id}
    ├── Run tenant migration template (creates errors, issues, metrics hypertables,
    │   continuous aggregates, alert_rules tables)
    └── INSERT INTO public.api_keys (org_id, key_hash, ...)
```

### Query Isolation

Every query from `QueryActor` sets `search_path` to the requesting org's schema before executing. This is enforced at the domain layer (`tenant.mesh`) — no raw SQL goes to the DB without schema routing.

### TimescaleDB and Schema-Per-Org

TimescaleDB hypertables and continuous aggregates are created per schema during tenant provisioning. Each org has its own `metrics` hypertable and `metrics_1m`/`metrics_1h` continuous aggregates. This means:
- Queries for org A's metrics never touch org B's hypertable chunks
- Continuous aggregate refresh is isolated per org (no cross-org lock contention)
- Downside: provisioning a new tenant is slightly heavier (creates ~5 TimescaleDB objects)

### Scale Boundary

Schema-per-org is well-suited for Mesher's target audience (self-hosted teams, SMB SaaS orgs). The pattern degrades at ~2,000–5,000 schemas per PostgreSQL instance. If Mesher's SaaS variant grows beyond that, the migration path is: introduce a `tenant_id` discriminator column on the metrics hypertable and consolidate to a shared schema (significant but well-understood migration).

---

## Real-Time Update Mechanism

### Recommended Transport: WebSocket (via Mesh built-in WebSocket support)

Streem-2 has a `fromWebSocket()` built-in adapter and Mesh has a built-in WebSocket server. This is the natural fit — no external library needed.

For metrics dashboards: WebSocket is appropriate because:
1. The client may want to send control messages (e.g., change time window, subscribe to different project) while staying subscribed
2. Mesh actors can receive internal messages from `MetricIngestActor` and push directly to the WS connection without polling
3. Streem-2's reactive signals update chart data in-place without re-rendering the full component tree

For error event notifications (new issue opened, alert fired): SSE is sufficient and simpler (unidirectional push), but WebSocket is acceptable for unification of transport.

**Recommended architecture:** Use a single WebSocket connection per browser session. Multiplex different subscription types (metrics updates, new error events, alert notifications) over one connection using a channel/topic envelope:

```json
{ "channel": "metrics", "project_id": "abc", "data": { ... } }
{ "channel": "alerts",  "org_id": "xyz",    "data": { ... } }
```

The `QueryActor` routes incoming subscription messages to the correct internal stream and dispatches outbound pushes back over the same connection.

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0–100 orgs | Single Mesh binary + single PG instance (Docker Compose default). All actors in one supervisor tree. |
| 100–1,000 orgs | PG connection pooling (PgBouncer in Docker Compose). TimescaleDB compression on old hypertable chunks (auto-policy). Increase `BatchWriterActor` flush size. |
| 1,000–5,000 orgs | Consider separating `IngestionActor` and `QueryActor` into separate Mesh processes (ingest vs. query separation) to avoid resource contention. PG with read replica for query. |
| 5,000+ orgs | Schema-per-org approach hits PG object count limits. Requires migration to shared schema + `tenant_id` discriminator on metrics, with RLS policies. This is a significant architectural shift — plan ahead. |

### Scaling Priorities

1. **First bottleneck:** `BatchWriterActor` write throughput. At high event rates, bulk insert sizes and flush intervals determine PG write performance. Fix: tune batch size, add PG connection pool, enable TimescaleDB compression policies.
2. **Second bottleneck:** `QueryActor` concurrent WS connections. Each open WebSocket holds a file descriptor and actor mailbox entry. Fix: configure OS file descriptor limits; horizontally scale `QueryActor` processes with a shared PubSub bus (e.g., PG LISTEN/NOTIFY or Redis Pub/Sub) to broadcast pushes across instances.
3. **Third bottleneck:** `AlertEvalActor` evaluation cost at many orgs with many rules. Fix: partition AlertEvalActor per org (one actor per active org), use TimescaleDB continuous aggregate queries (already fast).

---

## Anti-Patterns

### Anti-Pattern 1: Synchronous DB Writes in IngestionActor

**What people do:** Write each event directly to PostgreSQL inside the HTTP handler (synchronously, one insert per event).

**Why it's wrong:** At moderate throughput (1,000 events/sec), individual inserts saturate PG connection time. A slow insert blocks the ingestion actor's mailbox, creating backpressure that causes the OTLP client to time out and retry — amplifying load.

**Do this instead:** `IngestionActor` immediately ACKs the HTTP request and enqueues the event to `MetricIngestActor`/`ErrorIngestActor`. `BatchWriterActor` collects events in memory and bulk-inserts on size trigger or time trigger (e.g., 500 events or 100ms, whichever comes first).

---

### Anti-Pattern 2: Skipping Schema Routing Enforcement at Query Time

**What people do:** Pass `org_id` as a query parameter to SQL (`WHERE org_id = $1`) on a shared table, relying on the application to always include it.

**Why it's wrong:** A single missing WHERE clause exposes all orgs' data. This is a data breach risk for SaaS.

**Do this instead:** Enforce `SET search_path = org_{id}` at the connection level before any query executes. This makes it structurally impossible to query across schemas — even a bug cannot leak data. All query helpers in `db/queries/` must call the schema-routing helper as their first step.

---

### Anti-Pattern 3: Polling the DB for Dashboard Updates

**What people do:** Frontend polls `GET /api/v1/metrics` every 5 seconds to update charts.

**Why it's wrong:** At 100 concurrent dashboard users, this is 20 queries/second hitting PostgreSQL. At 1,000 users it becomes a denial-of-service against your own DB. Polling latency also means 5-second staleness minimum.

**Do this instead:** Use the WebSocket subscription mechanism. `MetricIngestActor` notifies `QueryActor` on every flush; `QueryActor` pushes deltas to subscribed connections. Dashboard updates are near-real-time (sub-second) and DB is queried only when new data arrives, not on a fixed interval.

---

### Anti-Pattern 4: Monolithic Error Processing in One Actor

**What people do:** Write a single `EventActor` that handles OTLP parsing, error fingerprinting, metric normalization, batch writing, and alert evaluation all in sequence.

**Why it's wrong:** A crash in the fingerprinting code takes down metric ingestion. A slow batch write blocks error processing. The actor becomes untestable and unmaintainable.

**Do this instead:** One actor per concern. `ErrorIngestActor` only does fingerprinting and grouping. `MetricIngestActor` only normalizes metrics. `BatchWriterActor` only writes. Each can be restarted independently under supervisor trees (Elixir-style "let it crash" philosophy).

---

### Anti-Pattern 5: Separate TimescaleDB Instance

**What people do:** Deploy TimescaleDB as a completely separate database container from the main PostgreSQL instance.

**Why it's wrong:** TimescaleDB is a PostgreSQL extension — it runs inside PostgreSQL. Treating it as a separate service adds unnecessary operational complexity (two databases, two connection pools, cross-DB joins impossible). Mesher's design decision (confirmed in PROJECT.md) is to use TimescaleDB as a PG extension within the single PostgreSQL instance.

**Do this instead:** Single PostgreSQL container with `timescaledb` extension enabled. In `docker-compose.yml`, use `timescale/timescaledb` image instead of stock `postgres`. No separate connection needed.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| OTLP clients (any language) | HTTP POST to `/v1/otlp` with `application/x-protobuf` or `application/json` body | Follow OTLP HTTP spec: gRPC (port 4317) is optional, HTTP (port 4318) is sufficient for Mesher's self-hosted use case |
| SMTP (email notifications) | NotifActor sends via Mesh's built-in HTTP client (or SMTP library if Mesh stdlib supports it) | Config via environment variables; no dependency on external service at startup |
| Webhook endpoints (Slack, PagerDuty, etc.) | NotifActor HTTP POST to configured URL | Org-level configuration; retry on failure with exponential backoff |
| AI services (SaaS only) | QueryActor proxies AI requests to LLM API (OpenAI/Anthropic) with error context | Feature-flagged off in self-hosted; only active in SaaS variant |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| IngestionActor ↔ ErrorIngestActor | Async actor message | Non-blocking; IngestionActor continues processing next event |
| IngestionActor ↔ MetricIngestActor | Async actor message | Same — fan-out is fire-and-forget from IngestionActor perspective |
| MetricIngestActor ↔ QueryActor | Async actor message ("new data for org X") | Notifies QueryActor to push to WS subscribers; no return value expected |
| QueryActor ↔ AlertEvalActor | AlertEvalActor polls DB independently; does not call QueryActor | AlertEvalActor sends fired/resolved events TO QueryActor for WS push |
| AlertEvalActor ↔ NotifActor | Async actor message | AlertEvalActor does not wait for delivery confirmation |
| All actors ↔ AuthActor | Synchronous call-response (blocking) | Token validation must complete before request is processed; cache validated tokens in AuthActor state to avoid repeated DB lookups |

---

## Sources

- OpenTelemetry Collector Architecture (official): https://opentelemetry.io/docs/collector/architecture/ — HIGH confidence
- SigNoz Architecture (official): https://signoz.io/docs/architecture/ — HIGH confidence
- Sentry Grouping System (official dev docs): https://develop.sentry.dev/backend/application-domains/grouping/ — HIGH confidence
- Sentry Fingerprint Rules (official): https://docs.sentry.io/concepts/data-management/event-grouping/ — HIGH confidence
- TimescaleDB Continuous Aggregates (official, via Tigerdata/Timescale docs): https://www.tigerdata.com/docs/use-timescale/latest/continuous-aggregates — HIGH confidence
- PostgreSQL Schema-Per-Tenant Multi-Tenancy (Crunchy Data blog): https://www.crunchydata.com/blog/designing-your-postgres-database-for-multi-tenancy — MEDIUM confidence (community blog, consistent with multiple sources)
- SSE vs WebSocket for observability dashboards: https://websocket.org/comparisons/sse/ — MEDIUM confidence
- Actor model / Elixir/Erlang high-throughput ingestion patterns: https://clouddevs.com/elixir/event-driven-applications-with-broadway/ — MEDIUM confidence (pattern applies; Mesh is not Elixir but uses same actor model)
- Multi-tenant WebSocket architecture patterns: https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/approaches/messaging — MEDIUM confidence

---

*Architecture research for: Mesher — self-hosted observability platform*
*Researched: 2026-03-03*

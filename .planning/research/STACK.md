# Stack Research

**Domain:** Self-hosted observability platform (Sentry + Datadog competitor)
**Researched:** 2026-03-03
**Confidence:** HIGH (OTLP spec from official docs; TimescaleDB patterns from official docs + multiple verified sources; infrastructure patterns from production platform analysis)

---

## Locked Stack (Not Researched — Accepted as Given)

| Component | Choice | Notes |
|-----------|--------|-------|
| Backend language | Mesh v12.0 | Actor model, native binary, built-in HTTP/WS/PG |
| Frontend framework | Streem-2 | Reactive signals + JSX |
| Component library | LitUI (lit-components) | Lit web components + Tailwind CSS v4 |
| Primary database | PostgreSQL + TimescaleDB | Time-series extension; Mesh has native PG driver |

The rest of this document covers the **additional infrastructure** needed beyond those locked choices.

---

## Recommended Stack

### Infrastructure Services

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Valkey | 8.x | In-process queue + API key cache | Drop-in Redis replacement under BSD license; Redis 8+ is AGPLv3 which is incompatible with MIT open-source core; Valkey 8 has 3x throughput improvement via I/O multithreading; used by Langfuse and other OTLP platforms |
| TimescaleDB | 2.x (latest) | Time-series extension on top of PostgreSQL | Already decided; 90%+ compression via columnar chunks; continuous aggregates for rollups; native retention policies; avoids ClickHouse dependency |

### OTLP Ingestion

The platform MUST implement the OTLP/HTTP endpoint natively in Mesh. This is the industry-standard ingestion protocol (OTLP spec 1.9.0, stable).

| Endpoint | Port | Path | Content-Type | Signal |
|----------|------|------|-------------|--------|
| HTTP/Protobuf | 4318 | `/v1/traces` | `application/x-protobuf` | Distributed traces |
| HTTP/Protobuf | 4318 | `/v1/metrics` | `application/x-protobuf` | Infrastructure metrics |
| HTTP/Protobuf | 4318 | `/v1/logs` | `application/x-protobuf` | Structured logs |
| HTTP/JSON | 4318 | Same paths | `application/json` | All signals (JSON encoding) |
| gRPC | 4317 | N/A | proto3 binary | All signals (gRPC transport) |

**Implement HTTP/protobuf first, gRPC second.** The OTel spec recommends `http/protobuf` as the default. gRPC requires HTTP/2 and is complex to implement; defer to Phase 2 or later. Browser clients (including Streem-2) cannot use gRPC — HTTP/protobuf covers all use cases.

Proto schema source: `github.com/open-telemetry/opentelemetry-proto` — use as a git submodule or copy the `.proto` files. Key message types:
- `ExportTraceServiceRequest` (traces)
- `ExportMetricsServiceRequest` (metrics)
- `ExportLogsServiceRequest` (logs)

Multiplexing: The same port 4318 SHOULD serve both `application/x-protobuf` and `application/json` — dispatch based on `Content-Type` header.

### Notification / Alerting Delivery

| Technology | Purpose | Why |
|------------|---------|-----|
| SMTP (external server) | Email alert delivery | Standard for self-hosted; user supplies their own SMTP server (Gmail, SES, Postmark, self-hosted Postfix); do NOT bundle a mail server |
| HTTP webhooks | Integration with Slack, PagerDuty, OpsGenie, etc. | Webhook is the universal integration primitive; one implementation covers all downstream tools |

No message-queue vendor needed for alerting delivery. Alert evaluation runs inside Mesh actors; delivery is synchronous HTTP POST (webhook) or SMTP send. For email, the platform requires these env vars at deploy time:

```
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=alerts@example.com
SMTP_PASS=secret
SMTP_FROM=alerts@example.com
SMTP_TLS=true
```

### Docker Compose Stack (Self-Hosted)

The self-hosted Docker Compose deployment has exactly 3 services:

```yaml
services:
  mesher:
    image: mesher/mesher:latest
    ports:
      - "8080:8080"   # Web UI + REST API
      - "4318:4318"   # OTLP/HTTP ingestion
      - "4317:4317"   # OTLP/gRPC ingestion (Phase 2)
    environment:
      DATABASE_URL: postgres://mesher:mesher@db:5432/mesher
      VALKEY_URL: valkey://valkey:6379
      # SMTP config
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT:-587}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASS: ${SMTP_PASS}
    depends_on:
      db:
        condition: service_healthy
      valkey:
        condition: service_healthy

  db:
    image: timescale/timescaledb:latest-pg16
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: mesher
      POSTGRES_USER: mesher
      POSTGRES_PASSWORD: mesher
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mesher"]
      interval: 10s
      timeout: 5s
      retries: 5

  valkey:
    image: valkey/valkey:8-alpine
    volumes:
      - valkeydata:/data
    command: valkey-server --maxmemory-policy noeviction
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  valkeydata:
```

**Why only 3 services:** Mesh's actor model handles the ingestion pipeline internally (no separate OTel Collector process needed). TimescaleDB handles all storage (no ClickHouse). Valkey handles queuing and caching (no Kafka). Compare: Sentry requires PostgreSQL + Kafka + Redis + ClickHouse + Snuba + Relay + ZooKeeper — 7+ services. Mesher achieves the same with 3.

**No object storage (S3/MinIO) needed for MVP.** Error event payloads and metric data are stored directly in PostgreSQL/TimescaleDB. Object storage is only needed if: (a) raw event archiving beyond DB retention is required, or (b) multi-modal attachments (screenshots, heap dumps) are supported. Both are out of scope for v1. MinIO Community Edition entered maintenance-only mode in December 2025 — do not add it unless necessary.

### Kubernetes Helm Chart (Production)

The Helm chart deploys the same 3 core services with the following additions for production scale:

| Component | What | Why |
|-----------|------|-----|
| `mesher` Deployment | 2–N replicas, HPA | Stateless Mesh actors scale horizontally |
| PostgreSQL | Bitnami PostgreSQL chart or CloudNativePG | Production HA, automated backups |
| TimescaleDB | `timescale/timescaledb-kubernetes` chart | TimescaleDB-aware HA, replication |
| Valkey | `bitnami/valkey` Helm chart | Production HA with Sentinel |
| Ingress | nginx-ingress or cloud LB | TLS termination; route 8080 (UI) and 4318 (OTLP) |

Do NOT add a separate OTel Collector sidecar for ingestion — Mesh handles this natively. An OTel Collector is only useful if you want to fan-out to multiple backends simultaneously, which is not the v1 use case.

---

## TimescaleDB-Specific Patterns

### Hypertable Setup for Metrics

```sql
-- Schema per organization (enforced at connection via search_path)
CREATE SCHEMA org_abc123;
SET search_path TO org_abc123;

-- Metrics hypertable
CREATE TABLE metrics (
    time        TIMESTAMPTZ NOT NULL,
    metric_name TEXT        NOT NULL,
    value       DOUBLE PRECISION NOT NULL,
    tags        JSONB,
    service     TEXT
);

SELECT create_hypertable(
    'metrics',
    'time',
    chunk_time_interval => INTERVAL '1 day'   -- optimal for observability workloads
);

-- Indexes
CREATE INDEX ON metrics (metric_name, time DESC);
CREATE INDEX ON metrics USING GIN (tags);

-- Compression: segment by metric_name so per-metric queries decompress only relevant segments
ALTER TABLE metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'metric_name, service',
    timescaledb.compress_orderby = 'time DESC'
);

-- Compress chunks older than 7 days automatically
SELECT add_compression_policy('metrics', INTERVAL '7 days');

-- Drop raw data after 90 days
SELECT add_retention_policy('metrics', INTERVAL '90 days');
```

**Why `chunk_time_interval = 1 day`:** TimescaleDB recommends setting the interval so one chunk fits in ~25% of available RAM. For observability workloads, 1-day chunks are the documented sweet spot — small enough for fast retention drops, large enough to avoid query planner overhead. The default of 7 days risks lock contention at high ingest rates.

### Continuous Aggregates for Dashboard Rollups

Dashboards should NEVER query raw metrics — always use continuous aggregates. Raw queries at scale are the #1 TimescaleDB performance pitfall.

```sql
-- 5-minute rollup (built on raw hypertable)
CREATE MATERIALIZED VIEW metrics_5m
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('5 minutes', time) AS bucket,
    metric_name,
    service,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value,
    COUNT(*)   AS sample_count
FROM metrics
GROUP BY bucket, metric_name, service
WITH NO DATA;

SELECT add_continuous_aggregate_policy('metrics_5m',
    start_offset => INTERVAL '1 hour',   -- re-process last hour for late data
    end_offset   => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes'
);

-- 1-hour rollup (built on top of 5-minute aggregate — more efficient than raw)
CREATE MATERIALIZED VIEW metrics_1h
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', bucket) AS bucket,
    metric_name,
    service,
    AVG(avg_value) AS avg_value,
    MIN(min_value) AS min_value,
    MAX(max_value) AS max_value,
    SUM(sample_count) AS sample_count
FROM metrics_5m
GROUP BY time_bucket('1 hour', bucket), metric_name, service
WITH NO DATA;

SELECT add_continuous_aggregate_policy('metrics_1h',
    start_offset => INTERVAL '2 hours',
    end_offset   => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);

-- Retention on rollups: keep 5m rollups for 30 days, 1h rollups for 1 year
SELECT add_retention_policy('metrics_5m', INTERVAL '30 days');
SELECT add_retention_policy('metrics_1h', INTERVAL '365 days');
```

**Hierarchy matters:** `metrics_1h` is built from `metrics_5m`, not from raw `metrics`. This is 10x more efficient than computing hourly rollups from raw data directly.

**Real-time aggregation (caution):** TimescaleDB v2.13+ has real-time aggregation DISABLED by default. Enable it per-view only if dashboard freshness is critical and you accept the query overhead:
```sql
ALTER MATERIALIZED VIEW metrics_5m SET (timescaledb.materialized_only = false);
```

### Error Events Table

```sql
CREATE TABLE error_events (
    time        TIMESTAMPTZ NOT NULL,
    project_id  UUID        NOT NULL,
    fingerprint TEXT        NOT NULL,   -- grouping key
    message     TEXT,
    level       TEXT,
    environment TEXT,
    stack_trace JSONB,
    metadata    JSONB
);

SELECT create_hypertable(
    'error_events',
    'time',
    chunk_time_interval => INTERVAL '1 day'
);

CREATE INDEX ON error_events (project_id, fingerprint, time DESC);
CREATE INDEX ON error_events (fingerprint, time DESC);

ALTER TABLE error_events SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'project_id, fingerprint',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('error_events', INTERVAL '7 days');
SELECT add_retention_policy('error_events', INTERVAL '90 days');
```

### Schema-per-Org Multi-Tenancy

Each organization gets its own PostgreSQL schema. Mesh sets `search_path = org_{id}` at connection time. This approach:
- Provides strong data isolation without separate databases
- Allows per-org retention/compression policies
- Supports Mesher-internal admin queries across all orgs via schema-qualified names
- Is the right choice at small-to-medium scale (hundreds of orgs); revisit at thousands

Org schema creation on signup:
```sql
CREATE SCHEMA org_{org_id};
-- Run CREATE TABLE ... for all tables in the new schema
```

---

## Valkey Usage Patterns

Valkey serves two distinct roles. Configure `maxmemory-policy noeviction` — do NOT use eviction for a queue.

### 1. Ingestion Queue (High-Priority)

Mesh actors write inbound OTLP batches to a Valkey list immediately on receipt, then acknowledge the HTTP request. A separate pool of processing actors drains the queue and writes to TimescaleDB. This decouples ingestion latency from DB write latency.

```
RPUSH mesher:ingest:metrics  <serialized batch>
RPUSH mesher:ingest:traces   <serialized batch>
RPUSH mesher:ingest:errors   <serialized batch>

-- Processors:
BLPOP mesher:ingest:metrics 0   -- blocking pop with no timeout
```

This is simpler and more appropriate than Kafka for Mesher's scale. Kafka adds ZooKeeper/KRaft coordination, partition management, and consumer group complexity. For a single self-hosted deployment ingesting thousands (not millions) of events per second, Valkey lists provide adequate throughput with far less operational overhead.

**Backpressure:** If the Valkey list length exceeds a configurable threshold (e.g., 100,000 items), the ingest endpoint returns `HTTP 503` with `Retry-After: 5`. This prevents unbounded memory growth.

### 2. API Key Cache

Every SDK request includes an API key. Verifying against PostgreSQL on every request is too slow. Cache API key → org mapping in Valkey with a 5-minute TTL:

```
SET mesher:apikey:{sha256_of_key} {org_id_json} EX 300
```

On revocation, delete the key explicitly:
```
DEL mesher:apikey:{sha256_of_key}
```

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Apache Kafka | Massively over-engineered for self-hosted scale; requires ZooKeeper or KRaft; 16GB RAM minimum for Sentry's setup; container count explodes | Valkey lists — adequate to 100k events/sec, ops-free |
| Redis 8+ (new versions) | AGPLv3 license conflicts with MIT open-source core | Valkey 8 — BSD license, drop-in compatible |
| ClickHouse | Avoids adding a second OLAP DB; TimescaleDB covers use case with SQL compatibility | TimescaleDB continuous aggregates |
| MinIO / S3 object storage | Not needed for MVP; MinIO Community Edition is maintenance-only as of Dec 2025 | PostgreSQL BYTEA for small attachments; defer object storage entirely |
| OpenTelemetry Collector (otelcol) | Adds another container; unnecessary when the backend natively speaks OTLP | Implement OTLP/HTTP receiver directly in Mesh |
| Elasticsearch / OpenSearch | Too heavy for error event search; PostgreSQL full-text search + GIN indexes on JSONB covers Mesher's needs | PostgreSQL `to_tsvector` + GIN index on `message` field |
| Prometheus | Not needed when TimescaleDB stores metrics; Prometheus is a collector, not a backend | TimescaleDB + OTLP ingestion directly |
| InfluxDB | Separate dependency; TimescaleDB outperforms InfluxDB at scale per 2025 benchmarks | TimescaleDB |

---

## Alternatives Considered

| Category | Recommended | Alternative | When Alternative Is Better |
|----------|-------------|-------------|---------------------------|
| Time-series storage | TimescaleDB (PG extension) | ClickHouse | You need petabyte-scale OLAP with columnar storage and no SQL compatibility requirement; Sentry's scale (>1M events/min) |
| Queue | Valkey lists | Kafka | Sustained millions of events/sec across multiple producers/consumers; you need message replay / consumer groups |
| Queue | Valkey lists | RabbitMQ | Complex routing rules, dead-letter queues, priority queues are required in MVP |
| Cache | Valkey | Memcached | You only need pure caching with no persistence; Valkey does everything Memcached does plus queuing |
| Email delivery | External SMTP | Bundled Postfix/Mailhog | Development/testing only; never in production self-hosted |
| Object storage | None (MVP) | MinIO (source build) or Garage | You need to store >1GB binary attachments or implement raw event archival beyond DB retention |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| TimescaleDB 2.x | PostgreSQL 15, 16, 17 | Use `timescale/timescaledb:latest-pg16` Docker image; PG16 is the stable choice as of 2026 |
| TimescaleDB 2.22+ | Real-time aggregation disabled by default | Explicitly enable per-view if needed |
| Valkey 8.x | Redis protocol (RESP2/RESP3) | All Redis 7.2-compatible clients work without changes |
| OTLP spec | 1.9.0 (stable for traces, metrics, logs) | Profiles signal is still in development — do not implement |
| OTLP/HTTP proto | proto3 | Use `opentelemetry-proto` repo as submodule; current release is v1.5.0 |

---

## Stack Patterns by Deployment Variant

**Self-hosted (Docker Compose, ≤1K events/sec):**
- 3 containers: mesher + timescaledb + valkey
- Single Mesh instance handles all roles (ingestion, API, UI serving, alert evaluation)
- Valkey with persistence (`appendonly yes`) for queue durability

**Self-hosted (Docker Compose, 1K–10K events/sec):**
- Same 3 containers, scale Mesh vertically (more CPU cores = more actors)
- Enable TimescaleDB compression aggressively (compress after 1 day instead of 7)
- Tune `chunk_time_interval` down to 12 hours if ingest is very high

**Production (Kubernetes, 10K+ events/sec):**
- Separate Mesh deployments for ingestion and API (different replicas counts)
- CloudNativePG or TimescaleDB Kubernetes operator for HA PostgreSQL
- Valkey Sentinel for HA cache/queue
- HPA on the ingestion Deployment based on Valkey queue depth

---

## Sources

- [OTLP Specification 1.9.0 — OpenTelemetry official](https://opentelemetry.io/docs/specs/otlp/) — HIGH confidence; endpoint paths, content types, ports, message types
- [opentelemetry-proto GitHub](https://github.com/open-telemetry/opentelemetry-proto) — HIGH confidence; canonical proto files
- [SigNoz gRPC vs HTTP comparison](https://signoz.io/comparisons/opentelemetry-grpc-vs-http/) — MEDIUM confidence; transport recommendations
- [TimescaleDB Compression docs (via tigerdata.com)](https://www.tigerdata.com/docs/use-timescale/latest/compression) — HIGH confidence; official TimescaleDB docs
- [TimescaleDB Continuous Aggregates](https://docs.timescale.com/use-timescale/latest/continuous-aggregates/) — HIGH confidence; official docs
- [TimescaleDB Multi-Tenancy guide (oneuptime.com)](https://oneuptime.com/blog/post/2026-02-02-timescaledb-multi-tenancy/view) — MEDIUM confidence; practical patterns verified against official docs
- [Chunk time interval best practices (tigerdata.com forum)](https://forum.tigerdata.com/forum/t/choosing-the-right-chunk-time-interval-value-for-timescaledb-hypertables/116) — HIGH confidence; from TimescaleDB team
- [Valkey vs Redis 2026 (Better Stack)](https://betterstack.com/community/comparisons/redis-vs-valkey/) — MEDIUM confidence; licensing analysis confirmed by official sources
- [Valkey official site](https://valkey.io/) — HIGH confidence; version 8 features
- [Langfuse self-hosting infrastructure](https://langfuse.com/self-hosting) — MEDIUM confidence; reference implementation for observability platform with Valkey queue pattern
- [Sentry self-hosted docker-compose.yml](https://github.com/getsentry/self-hosted/blob/master/docker-compose.yml) — HIGH confidence; confirms what services a Sentry-class platform needs
- [MinIO maintenance mode (InfoQ, Dec 2025)](https://www.infoq.com/news/2025/12/minio-s3-api-alternatives/) — MEDIUM confidence; confirmed MinIO Community Edition maintenance status
- [OTel backpressure handling](https://oneuptime.com/blog/post/2026-02-06-backpressure-handling-opentelemetry-pipelines/view) — MEDIUM confidence; ingest pipeline design patterns

---

*Stack research for: Mesher self-hosted observability platform*
*Researched: 2026-03-03*

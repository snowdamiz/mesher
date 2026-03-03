# Project Research Summary

**Project:** Mesher
**Domain:** Self-hosted observability platform (error tracking + infrastructure metrics)
**Researched:** 2026-03-03
**Confidence:** HIGH

## Executive Summary

Mesher is a self-hosted observability platform targeting teams who need a simpler, cheaper alternative to Sentry + Datadog. The core competitive position is combining error tracking and infrastructure metrics in a single tool that deploys with `docker compose up` on a $10/month VPS — compared to Sentry's 16+ container, 16GB RAM requirement. Research confirms this niche is real and underserved: GlitchTip handles errors but has no metrics; SigNoz has metrics but weak error grouping and heavy ClickHouse dependency; self-hosted Sentry is actively discouraged by Sentry's own CEO. The recommended approach is Mesh backend with TimescaleDB (as a PostgreSQL extension) for time-series storage and Valkey for the ingestion queue — three services total.

The architecture is actor-per-concern: dedicated Mesh actors for ingestion, error fingerprinting, metric normalization, batch writing, query/API, alerting evaluation, and notification delivery. Each actor can restart independently without affecting others. Multi-tenancy uses schema-per-org PostgreSQL isolation (one schema per organization), which provides strong data boundaries suitable for regulated industries and is operationally sound up to ~2,000–5,000 orgs. The OTLP HTTP endpoint (port 4318) must be implemented natively in Mesh — no external OTel Collector needed. Sentry envelope format compatibility (`/api/{project_id}/envelope/`) is a critical differentiator enabling zero-friction migration.

The highest-risk areas are: (1) beta toolchain limitations in Mesh, Streem-2, and LitUI that must be spiked in Phase 1 before any production code is written, (2) error fingerprinting quality — getting grouping wrong in either direction makes the core feature useless and is expensive to retrofit, and (3) schema-per-org migration complexity at scale, which requires a migration orchestrator built from day one. Cardinality explosion in metrics and alert spam (stateless alerting) are both "never acceptable" design shortcuts that must be designed out from the start, not added later.

## Key Findings

### Recommended Stack

The stack is largely locked: Mesh v12.0 backend, Streem-2 frontend, LitUI component library, PostgreSQL + TimescaleDB. The additional infrastructure needed is minimal: Valkey 8 (BSD-licensed Redis replacement) for the ingestion queue and API key cache, and external SMTP for email alert delivery. No Kafka, no ClickHouse, no MinIO, no separate OTel Collector — each of these would undermine Mesher's core "runs anywhere" pitch.

OTLP ingestion must implement HTTP/protobuf first (port 4318), JSON second, and gRPC (port 4317) deferred to Phase 2 or later. Browser clients cannot use gRPC, so HTTP covers all use cases for v1. Proto definitions come from the official `opentelemetry-proto` repository as a git submodule. Valkey must be configured with `maxmemory-policy noeviction` since it serves as a durable queue, not just a cache.

**Core technologies:**
- TimescaleDB 2.x (PG extension): time-series metrics storage with automatic compression, continuous aggregates for dashboard rollups, and retention policies — avoids ClickHouse entirely
- Valkey 8.x: ingestion queue (RPUSH/BLPOP pattern) + API key cache (5-minute TTL) — BSD licensed, 3x Redis throughput, drop-in compatible
- OTLP/HTTP (spec 1.9.0): industry-standard ingestion protocol; implement HTTP/protobuf on port 4318 first
- External SMTP: email alert delivery via user-supplied SMTP server; no bundled mail server
- HTTP webhooks: universal integration primitive for Slack, PagerDuty, OpsGenie, etc.

### Expected Features

Research identifies a clear MVP boundary. The v1 feature set is what's needed for a team to replace self-hosted Sentry and add basic infrastructure metrics. Everything else is v1.x or v2+.

**Must have (table stakes):**
- Error ingestion supporting both Sentry envelope format AND OTLP — both required for migration story
- Issue deduplication by fingerprint (exception type + normalized top N app frames)
- Issue lifecycle: open / resolved / ignored / auto-reopen on recurrence
- Issue list with filtering (project, environment, status, time range)
- Error timeline: first seen, last seen, occurrence count, sparkline
- Environment tagging for production vs. staging separation
- Multi-project, multi-org support with API key / DSN auth
- Infrastructure metrics ingestion: fixed schema (CPU, memory, throughput, response time, error rate)
- Time-series dashboards: line and area charts, configurable time windows
- Alert rules on error rate and metric thresholds with email + webhook channels
- User accounts, organizations, invite flow
- Docker Compose self-hosted deployment (single command)

**Should have (competitive differentiators):**
- Sentry SDK drop-in compatibility (`/api/{project_id}/envelope/`) — enables 10-minute migration
- Capacity / scaling indicators derived from metrics
- Kubernetes Helm chart for production HA deployment
- Slack notification channel
- AI root cause analysis (SaaS tier only — requires stable error schema first)
- Anomaly detection (SaaS tier only — requires weeks of baseline data)
- Mesh-native SDK for actor crash reporting and HTTP middleware auto-instrumentation
- Schema-per-org data isolation as a compliance differentiator

**Defer (v2+):**
- AI chat agent / MCP integration — requires mature data model + all AI features working
- Distributed tracing / APM span visualization — major build, separate product surface
- Fine-grained RBAC — two roles (admin/member) sufficient for v1
- SSO / SAML — SaaS enterprise tier only
- Custom metrics (user-defined) — cardinality risk; fixed schema sufficient for v1
- Session replay / RUM — out of scope; server-side only
- Log management pipeline — different product category entirely
- Issue comments / collaboration — social layer, defer until core UX is excellent

### Architecture Approach

The architecture is a four-layer system: ingestion layer (OTLP/HTTP endpoint → IngestionActor fan-out → typed ingest actors), storage layer (PostgreSQL with per-org schemas + TimescaleDB hypertables), query layer (QueryActor handling REST API + WebSocket subscriptions + alert evaluation + notifications), and presentation layer (Streem-2 frontend with reactive signals). Actors communicate asynchronously; only AuthActor uses synchronous call-response. The BatchWriterActor pattern is critical: ingest actors never write directly to PostgreSQL — they buffer and bulk-flush, decoupling ingestion latency from DB write latency.

**Major components:**
1. IngestionActor — HTTP listener on port 4318, envelope validation, fan-out to ErrorIngestActor and MetricIngestActor
2. ErrorIngestActor — SHA1 fingerprinting (exception type + normalized app frames), deduplication, issue grouping
3. MetricIngestActor — metric normalization, in-memory batch buffer, flush to TimescaleDB hypertables
4. BatchWriterActor — bulk PostgreSQL inserts, flush on size (500 events) or timer (100ms)
5. QueryActor — REST API handler, WebSocket connection registry per org, subscription dispatch
6. AlertEvalActor — periodic evaluation loop against metrics_1m/metrics_1h continuous aggregates, state machine (inactive → pending → firing → resolved)
7. NotifActor — email + webhook delivery with dedup window; stateless delivery
8. AuthActor — API key + session token validation, in-process cache to avoid per-request DB lookups
9. TenantProvisionActor — creates org schema + runs tenant migration template on signup
10. Streem-2 frontend — fromWebSocket() adapter for real-time metrics; fromSSE() for error notifications; LitUI charts with 500ms batched updates

### Critical Pitfalls

1. **Beta toolchain limitations discovered late** — Spike all critical Mesh/Streem-2/LitUI capabilities in Phase 1 before any production code: WebSocket actor supervision, mailbox backpressure, PG transaction pooling with dynamic search_path, chart live-update performance, and data-table scale. A limitation discovered in Phase 5 is a rewrite, not a bug fix.

2. **Error fingerprinting wrong in either direction** — Too broad (all NullPointerExceptions in one issue) or too narrow (new issue per deploy) both make the core feature useless. Fingerprint on exception type + top 3–5 normalized application frames (strip line numbers, strip framework frames). Test with real error corpora before shipping the issues list. Retrofitting requires re-processing all historical data.

3. **Alert spam from stateless alerting** — Implement the full state machine (inactive → pending → firing → resolved) before sending the first notification. Only notify on state transitions, not every evaluation. Add a `for` duration (condition must hold for N consecutive evaluations) and re-notification cooldown. Stateless alerting is log spam that destroys user trust within the first real incident.

4. **Cardinality explosion in metrics** — Define a strict label allowlist at ingestion and reject unknown labels with HTTP 400. Never allow unbounded labels (user_id, request_id, container_id) as metric dimensions. This must be designed into the ingestion schema before accepting the first metric — retrofitting requires dropping and recreating hypertables.

5. **Schema-per-org migration complexity** — Build a migration orchestrator (a Mesh actor with per-org version tracking) before org #2 is onboarded. Migrations must be idempotent, async (never block app boot), and backward-compatible (add nullable columns; never rename or drop). Use `SET LOCAL search_path` (not `SET search_path`) for PgBouncer transaction pooling compatibility.

6. **OTLP ingestion without backpressure** — Implement per-org rate limiting (HTTP 429 with Retry-After) and actor mailbox bounds from day one. An ingest endpoint that accepts everything and drops silently is broken by design. Expose `/health/ingest` for degraded status detection.

## Implications for Roadmap

Based on the dependency graph in FEATURES.md, the build order in ARCHITECTURE.md, and the phase-to-pitfall mapping in PITFALLS.md, the following phase structure is recommended:

### Phase 1: Foundation + Toolchain Spike
**Rationale:** All subsequent phases depend on the database schema, auth, and tenant provisioning being correct. Beta toolchain limitations must be discovered NOW — a WebSocket supervision limitation found in Phase 6 is catastrophic. This phase proves the toolchain before committing to it.
**Delivers:** Global database schema (orgs, users, projects, api_keys), AuthActor, TenantProvisionActor, migration orchestrator skeleton, Docker Compose stack running locally, and passing integration tests for every critical Mesh/Streem-2/LitUI capability.
**Addresses:** Multi-project/multi-org, Docker Compose deployment (skeleton), user accounts
**Avoids:** Beta toolchain limitation discovered late (Pitfall 10), schema-per-org migration complexity (Pitfall 3), connection pool exhaustion (Pitfall 4)
**Research flag:** Needs `/gsd:research-phase` — Mesh WebSocket actor APIs, PgBouncer transaction pooling with SET LOCAL, and LitUI chart performance are unverified at the required scale.

### Phase 2: Error Ingestion Core
**Rationale:** Error ingestion is the primary feature dependency — issue grouping, lifecycle management, and alerting all require it. Sentry envelope format compatibility must be implemented alongside OTLP, not as an afterthought, because it is the migration story.
**Delivers:** OTLP/HTTP endpoint (port 4318), Sentry envelope endpoint (`/api/{project_id}/envelope/`), IngestionActor, ErrorIngestActor with fingerprinting algorithm, BatchWriterActor, error events hypertable with retention policy.
**Addresses:** Error ingestion (both formats), environment tagging, API key/DSN auth
**Avoids:** OTLP version mismatch (Pitfall 6), OTLP ingestion without backpressure (Pitfall 5), poor error fingerprinting (Pitfall 9), unbounded event storage (Pitfall 2)
**Research flag:** Standard patterns — OTLP spec is well-documented. Fingerprinting algorithm needs validation against real error corpora; no external research phase needed, but testing rigor is high.

### Phase 3: Issue Management + REST API
**Rationale:** Once errors are ingested, users need to see and manage them. QueryActor and the REST API are prerequisites for the frontend. Issue lifecycle (open/resolved/ignored/auto-reopen) must be implemented before any UI — it is the core error management loop.
**Delivers:** QueryActor with REST API, issue grouping/deduplication in storage, issue lifecycle state machine, issue list with filtering (project, environment, status, time range), error timeline (first seen, last seen, count, sparkline).
**Addresses:** Issue lifecycle management, issue list with filtering, error timeline, environment tagging in UI
**Avoids:** SELECT * in issues list (use indexed columns only, fetch full payload on demand), no time-range index on events table

### Phase 4: Metrics Ingestion + Dashboards
**Rationale:** Infrastructure metrics are the second core feature pillar and the primary Datadog-competitive story. MetricIngestActor depends on BatchWriterActor (Phase 2) and TimescaleDB hypertables. Dashboards require the QueryActor REST API (Phase 3).
**Delivers:** MetricIngestActor, fixed-schema metric hypertable (CPU, memory, throughput, response time, error rate), continuous aggregates (metrics_5m, metrics_1h), time-series dashboard with line/area charts, configurable time windows.
**Addresses:** Infrastructure metrics ingestion, time-series dashboards
**Avoids:** Cardinality explosion (label allowlist enforced at ingestion), querying raw metrics for dashboards (use continuous aggregates only), unbounded metric storage (retention policies from day one)
**Research flag:** Standard TimescaleDB patterns — well-documented. No additional research phase needed.

### Phase 5: Real-Time Push
**Rationale:** WebSocket push for live dashboard updates requires QueryActor (Phase 3) and MetricIngestActor notify calls (Phase 4). This phase also introduces the pub/sub architecture that must be designed for fan-out from the start — retrofitting is expensive.
**Delivers:** WebSocket connection registry in QueryActor, pub/sub channel architecture (org:id:events topics), Streem-2 fromWebSocket() adapter with reconnection handling, batched 500ms dashboard updates, real-time error event notifications via SSE.
**Addresses:** Real-time error ingestion (sub-5s latency to dashboard visibility)
**Avoids:** WebSocket fan-out bottleneck (Pitfall 7 — pub/sub architecture required before first WS connection), polling the DB for dashboard updates (anti-pattern 3), LitUI chart render thrash (500ms batching)
**Research flag:** Needs `/gsd:research-phase` — Mesh WebSocket actor fan-out patterns and Streem-2 reconnection behavior under connection drops are beta tool behaviors that must be validated.

### Phase 6: Alerting
**Rationale:** Alerting depends on both error data (Phase 3) and metric data (Phase 4) being available. The alert state machine must be complete before the first notification is sent — stateless alerting is never acceptable.
**Delivers:** AlertEvalActor with state machine (inactive → pending → firing → resolved), alert rules UI, email notification channel (SMTP), webhook notification channel, NotifActor with dedup window, re-notification cooldown, `for` duration support.
**Addresses:** Alert rules on error rate and metric thresholds, email + webhook channels
**Avoids:** Alert spam (Pitfall 8 — state machine mandatory), alert notifications with no context (include metric value, threshold, time window, dashboard link), no rate limit on ingestion (verify 429 before shipping)

### Phase 7: Frontend Polish + Deployment
**Rationale:** Full frontend integration requires all backend APIs (Phases 3–6) to be stable. Docker Compose must be validated end-to-end before any marketing or users. This phase completes the v1 product.
**Delivers:** Complete Streem-2 UI (dashboard, error list, issue detail, alert management, settings, org/project management), Docker Compose stack with health checks, empty states for new installs, skeleton loading states, "no data yet" UX.
**Addresses:** Docker Compose self-hosted deployment (fully working), all UI polish items
**Avoids:** Dashboard with no loading state (skeleton loaders required), no empty states (new project must show setup instructions, not blank charts), live updates interrupting user interaction (pause on form focus)

### Phase 8: SDK + Kubernetes
**Rationale:** Mesh-native SDK requires the HTTP API to be stable (Phase 7). Kubernetes Helm chart is a v1.x feature but benefits from being developed while Docker Compose configuration is fresh.
**Delivers:** Mesh-native SDK (actor crash reporter + HTTP middleware auto-instrumentation), Kubernetes Helm chart with HPA on ingestion, production HA documentation.
**Addresses:** Mesh-native SDK (unique differentiator), Kubernetes Helm chart (enterprise deployment)
**Research flag:** Standard patterns for Helm chart. SDK design is novel — needs Phase 1 spike to validate Mesh actor supervision model for crash capture.

### Phase Ordering Rationale

- Phases 1–3 form the minimum viable loop: ingest errors, query them, manage issues. Nothing else works without this.
- Phase 4 (metrics) requires Phase 2 (BatchWriterActor) and Phase 3 (QueryActor) — natural ordering.
- Phase 5 (real-time) is deliberately separated from Phase 4 because the fan-out architecture must be designed intentionally, not bolted onto the metrics ingestion as an afterthought.
- Phase 6 (alerting) is last among backend phases because it depends on both error and metric data accumulating — you cannot test alert evaluation with zero data.
- Phase 7 (frontend/deployment) comes after all APIs stabilize — frontend built against unstable APIs wastes effort.
- The fingerprinting algorithm (Phase 2) and alert state machine (Phase 6) are each "never retrofit" — they must be correct from day one. Both are called out explicitly in their phases.

### Research Flags

Phases likely needing `/gsd:research-phase` during planning:
- **Phase 1:** Mesh WebSocket actor supervision model, PgBouncer transaction pooling with SET LOCAL, LitUI chart live-update performance at scale, Streem-2 fromWebSocket() reconnection behavior — beta tool APIs that are unverified at production requirements
- **Phase 5:** WebSocket pub/sub fan-out patterns in Mesh specifically, Streem-2 SSE vs WebSocket trade-offs for error notifications

Phases with standard, well-documented patterns (skip research-phase):
- **Phase 2:** OTLP spec is official and stable; Sentry envelope format is documented
- **Phase 4:** TimescaleDB continuous aggregates are extensively documented with official examples
- **Phase 6:** Alert state machine pattern (Prometheus/Grafana model) is well-established
- **Phase 7:** Docker Compose, Helm chart — standard tooling
- **Phase 8:** Helm chart patterns are standard; SDK design can reuse Phase 1 spike findings

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | OTLP spec from official docs; TimescaleDB patterns from official docs + TimescaleDB team; Valkey from official site + licensing confirmed; Docker Compose architecture from Sentry self-hosted analysis |
| Features | MEDIUM-HIGH | Table stakes verified against Sentry docs + multiple competitor analyses; differentiators cross-referenced against GlitchTip/SigNoz complaints; some sources are competitor blogs (biased framing) |
| Architecture | HIGH | Patterns verified against SigNoz official docs, OTel official docs, Sentry dev docs, TimescaleDB docs, Crunchy Data PostgreSQL multi-tenancy guide |
| Pitfalls | MEDIUM-HIGH | Most pitfalls from authoritative vendor engineering sources (Datadog, Grafana, Crunchy Data); some from community sources (Hacker News, Medium) that are internally consistent with technical analysis |

**Overall confidence:** HIGH

### Gaps to Address

- **Mesh actor mailbox backpressure API:** Exact Mesh v12.0 API for configuring mailbox bounds and backpressure signals is unverified — must be spiked in Phase 1 before designing the ingestion pipeline.
- **Streem-2 fromWebSocket() reconnection behavior:** Whether the adapter handles reconnection with state replay or requires application-level handling is unverified — must be spiked in Phase 1.
- **LitUI chart performance with live data at scale:** Whether LitUI chart components support efficient partial data updates (append new points without full re-render) is unverified — must be spiked before Phase 5.
- **TimescaleDB schema-per-org at 500+ schemas:** Provisioning time for hypertables + continuous aggregates per org schema at signup has not been benchmarked — may need caching or async provisioning for high-signup-rate SaaS scenarios.
- **Sentry envelope format edge cases:** The Sentry envelope format has undocumented edge cases discovered through implementation (GlitchTip and Bugsink both note this). Plan for iteration on envelope parsing after first real-world Sentry SDK compatibility testing.
- **PII scrubbing at ingestion:** Research identifies PII scrubbing as a security requirement but does not specify the exact scrubbing patterns needed. GDPR compliance scope should be defined before the error ingestion endpoint ships.

## Sources

### Primary (HIGH confidence)
- OpenTelemetry OTLP Specification 1.9.0 — endpoint paths, content types, ports, message types
- opentelemetry-proto GitHub — canonical proto files, v1.5.0 current release
- TimescaleDB official docs (via Tigerdata/Timescale) — compression, continuous aggregates, retention, chunk intervals
- Valkey official site — version 8 features, I/O multithreading, licensing
- Sentry self-hosted docker-compose.yml — confirms 7+ service requirement at Sentry scale
- Sentry Issue Grouping + Fingerprint Rules official docs
- SigNoz official architecture docs
- Datadog DASH 2025 official blog — AI observability feature reference
- Grafana alerting best practices — official docs
- Crunchy Data PostgreSQL multi-tenancy guide — schema-per-org patterns
- Datadog Observability Pipelines docs — backpressure handling

### Secondary (MEDIUM confidence)
- Better Stack: Valkey vs Redis 2026 — licensing analysis
- Langfuse self-hosting infrastructure — Valkey queue pattern reference
- Crunchy Data / DZone: PgBouncer at scale + transaction pooling
- Bugsink: GlitchTip vs Sentry vs Bugsink — competitor analysis
- Hacker News: Self-hosted Sentry complaints thread — community experience
- VictoriaMetrics blog: alerting best practices
- OneUptime: TimescaleDB retention, backpressure handling in OTLP pipelines
- ClickHouse Engineering: high-cardinality observability challenges
- SigNoz self-hosted limitations knowledge base

### Tertiary (LOW confidence)
- Datadog AI observability tools 2026 (Dash0) — competitor marketing, directionally useful
- WebSocket scaling patterns (Medium/Syntal) — single community source, consistent with architecture patterns
- Infrastructure monitoring best practices (MOSS, Middleware) — general guidance only

---
*Research completed: 2026-03-03*
*Ready for roadmap: yes*

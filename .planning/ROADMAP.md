# Roadmap: Mesher

## Overview

Mesher is built in nine phases that follow a strict dependency order: foundation and toolchain validation first, then error ingestion, issue management, metrics, real-time push, alerting, frontend integration, SDK and Kubernetes, and finally AI features. The first phase is mandatory and non-negotiable — all three tools (Mesh, Streem-2, LitUI) are in beta and critical capabilities must be spiked before any production code is written. Each subsequent phase delivers a coherent, independently verifiable capability. The AI phase (Phase 9) is SaaS-tier only and gated on a stable error schema established in Phase 3.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation + Toolchain Spike** - Auth, orgs, Docker Compose skeleton, and beta toolchain validation
- [ ] **Phase 1.1: Update project to use Mesh built-in ORM for migrations and queries** (INSERTED)
- [x] **Phase 1.2: Reorganize repo with server and client directories** (INSERTED)
- [ ] **Phase 2: Error Ingestion Core** - OTLP/HTTP + Sentry envelope ingestion, fingerprinting, event storage
- [ ] **Phase 3: Issue Management + REST API** - Issue list, lifecycle, filtering, timeline, QueryActor REST API
- [ ] **Phase 4: Metrics Ingestion + Dashboards** - Fixed-schema metrics, TimescaleDB hypertables, line/area charts
- [ ] **Phase 5: Real-Time Push** - WebSocket pub/sub, live dashboard updates, SSE error notifications
- [ ] **Phase 6: Alerting + Notifications** - Alert state machine, email/webhook/Slack notifications
- [ ] **Phase 7: Frontend Polish + Deployment** - Complete Streem-2 UI, Docker Compose validation, empty states
- [ ] **Phase 8: SDK + Kubernetes** - Mesh-native SDK, Kubernetes Helm chart with HPA
- [ ] **Phase 9: AI Features (SaaS)** - Root cause analysis, anomaly detection, noise reduction, AI chat agent

## Phase Details

### Phase 1: Foundation + Toolchain Spike
**Goal**: Users can create accounts, form organizations, and deploy the stack locally — while every critical beta toolchain capability is proven before any production code is written
**Depends on**: Nothing (first phase)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, ORG-01, ORG-02, ORG-03, ORG-04, ORG-05, ORG-06, DEPLOY-01, DEPLOY-02, DEPLOY-03
**Success Criteria** (what must be TRUE):
  1. User can register an account with email/password, log in, maintain session across browser refreshes, log out from any page, and reset their password via email link
  2. User can create an organization, invite members by email, and have invited users accept and join; each organization is provisioned with its own isolated PostgreSQL schema at signup
  3. User can create projects scoped to their organization and generate/revoke API keys and DSNs per project
  4. The full stack runs with `docker compose up` using three services (app, TimescaleDB, Valkey) with health checks and dependency ordering; all config is environment-variable driven
  5. Mesh WebSocket actor supervision, PG transaction pooling with SET LOCAL, Streem-2 fromWebSocket() reconnection, and LitUI chart live-update performance are each demonstrated in a passing spike test
**Plans**: 6 plans

Plans:
- [x] 01-01-PLAN.md -- Docker Compose stack + project scaffold + DB migrations + tenant isolation
- [x] 01-02-PLAN.md -- Toolchain spikes (WS actor supervision, PG SET LOCAL, WS reconnect, chart live-update)
- [x] 01-03-PLAN.md -- Auth system (register, login, logout, sessions, middleware)
- [x] 01-04-PLAN.md -- Organization management + schema provisioning
- [x] 01-05-PLAN.md -- Password reset, Google OAuth, invites, projects, API keys
- [x] 01-06-PLAN.md -- Frontend UI (auth pages, org setup wizard, org settings)

### Phase 01.2: Reorganize repo with server and client directories (INSERTED)

**Goal:** Reorganize the repository into explicit `server/` and `client/` roots while preserving current runtime behavior, path semantics, and developer workflow
**Requirements**: N/A (inserted structural phase — no new product requirements)
**Depends on:** Phase 1
**Plans:** 3/3 plans complete

Plans:
- [x] 01.2-01-PLAN.md -- Filesystem migration to `server/` + `client/` and server-spike relocation
- [x] 01.2-02-PLAN.md -- Compose/Docker/service wiring and root scoped command wrappers
- [x] 01.2-03-PLAN.md -- Docs terminology standardization and full regression verification matrix

### Phase 01.1: Update project to use Mesh built-in ORM for migrations and queries (INSERTED)

**Goal:** Replace all hand-written raw SQL (migrations, queries, transactions) with Mesh's built-in ORM across the entire codebase, eliminate schema-per-org isolation in favor of org_id FK filtering, and flatten deeply nested error handling
**Requirements**: N/A (inserted refactoring phase — no new features, scope defined in CONTEXT.md)
**Depends on:** Phase 1
**Plans:** 4/4 plans complete

Plans:
- [x] 01.1-01-PLAN.md -- Model struct definitions (types/) and fresh ORM migration
- [x] 01.1-02-PLAN.md -- Centralized storage/queries.mpl and remove schema-per-org
- [x] 01.1-03-PLAN.md -- Auth module conversion (session, reset, oauth, cookies)
- [x] 01.1-04-PLAN.md -- Org/project handler conversion and main.mpl cleanup

### Phase 2: Error Ingestion Core
**Goal**: The system accepts error events via both OTLP and Sentry envelope formats, fingerprints them into issues, and persists them with environment tagging and rate limiting
**Depends on**: Phase 1
**Requirements**: INGEST-01, INGEST-02, INGEST-03, INGEST-04, INGEST-05, INGEST-06, INGEST-07, ERR-01, ERR-02, ERR-10
**Success Criteria** (what must be TRUE):
  1. An existing Sentry SDK can be pointed at Mesher (`/api/{project_id}/envelope/`) without code changes and errors appear in the database
  2. An OTLP/HTTP client (protobuf or JSON) can send error events to port 4318 and they are stored with stack trace, message, severity, exception type, and metadata
  3. Events tagged with the same environment string (production, staging, development) are stored with that tag and can be distinguished in the database
  4. The system deduplicates events into issues by fingerprint (exception type + normalized top 3–5 app frames, line numbers stripped); two events with the same logical error produce one issue, not two
  5. Per-org ingest rate limiting returns HTTP 429 with Retry-After when exceeded; `/health/ingest` reports pipeline health status
**Plans**: TBD

### Phase 3: Issue Management + REST API
**Goal**: Users can view, filter, search, and manage the lifecycle of grouped error issues through a stable REST API
**Depends on**: Phase 2
**Requirements**: ERR-03, ERR-04, ERR-05, ERR-06, ERR-07, ERR-08, ERR-09
**Success Criteria** (what must be TRUE):
  1. User can view the issue list grouped by fingerprint showing occurrence count per issue; each issue shows first seen, last seen, total count, and an occurrence sparkline
  2. User can filter the issue list by project, severity level, environment, status, and time range; user can search by error message substring
  3. User can transition a single issue through open → resolved → ignored; a resolved or ignored issue automatically re-opens when a new matching event arrives
  4. User can bulk-update issue status (bulk resolve, bulk ignore) from the issue list in a single action
**Plans**: TBD

### Phase 4: Metrics Ingestion + Dashboards
**Goal**: The system ingests infrastructure metrics with a fixed schema, stores them in TimescaleDB with rollups and retention, and presents them as interactive time-series charts
**Depends on**: Phase 3
**Requirements**: METRICS-01, METRICS-02, METRICS-03, METRICS-04, METRICS-05, DASH-01, DASH-02, DASH-03, DASH-05
**Success Criteria** (what must be TRUE):
  1. An OTLP/HTTP client can send CPU, memory, throughput, response time, and error rate metrics to port 4318; events with unknown label keys are rejected with HTTP 400
  2. Raw metrics are stored in a TimescaleDB hypertable; continuous aggregates at 5-minute and 1-hour intervals exist and are queryable; retention policy of 90 days raw / 365 days aggregates is applied
  3. User can view a time-series line chart and area chart for any metric on the project dashboard, selecting a time window from 1h, 6h, 24h, 7d, or 30d
  4. User can view capacity/scaling indicator gauges showing CPU headroom, memory headroom, and throughput trend (toward limit / stable / declining)
**Plans**: TBD

### Phase 5: Real-Time Push
**Goal**: Users see new error events and metric updates in the dashboard within 5 seconds of ingestion without polling, via WebSocket pub/sub and SSE
**Depends on**: Phase 4
**Requirements**: ERR-11, DASH-04
**Success Criteria** (what must be TRUE):
  1. New error events are visible in the issue list within 5 seconds of ingestion via server-sent events push; no browser polling occurs
  2. Metric charts auto-update in real time via WebSocket push, with updates batched to at most one per 500ms; the connection recovers automatically after a network drop
**Plans**: TBD

### Phase 6: Alerting + Notifications
**Goal**: Users can define alert rules that fire only when conditions are confirmed, with notifications delivered via email, webhook, and Slack — with dedup and re-notification controls
**Depends on**: Phase 4
**Requirements**: ALERT-01, ALERT-02, ALERT-03, ALERT-04, ALERT-05, NOTIF-01, NOTIF-02, NOTIF-03, NOTIF-04
**Success Criteria** (what must be TRUE):
  1. User can define an alert rule on error rate or a metric value (CPU, memory, throughput, response time) with a threshold, time window, and `for` duration; the rule fires only after the condition holds for N consecutive evaluations
  2. Alert evaluation uses the full state machine (inactive → pending → firing → resolved); notifications are sent on state transitions only, not on every evaluation cycle
  3. User can configure a per-rule re-notification cooldown; the system deduplicates notifications within a configurable dedup window to prevent duplicate delivery during rapid state transitions
  4. System delivers notifications via SMTP email, HTTP webhook, and Slack API with formatted messages including metric value, threshold, time window, and a direct dashboard link
**Plans**: TBD

### Phase 7: Frontend Polish + Deployment
**Goal**: The complete Streem-2 UI is integrated and polished across all features, and the Docker Compose stack is validated end-to-end for a first-time self-hosted installation
**Depends on**: Phase 6
**Requirements**: (none — all v1 requirements are mapped in Phases 1–6 and 8–9; this phase integrates and completes the UI across all previously-delivered backend APIs)
**Success Criteria** (what must be TRUE):
  1. A first-time user can run `docker compose up`, open the browser, register an account, create an org and project, and reach a working dashboard with setup instructions — not a blank or broken screen
  2. Every feature built in Phases 1–6 has a complete Streem-2 UI: dashboard, issue list, issue detail, alert management, org/project settings, and API key management
  3. All data-loading states show skeleton loaders; all empty states show contextual setup instructions; live updates pause gracefully when a form or dialog is focused
**Plans**: TBD

### Phase 8: SDK + Kubernetes
**Goal**: The Mesh-native SDK enables zero-config actor crash reporting and HTTP auto-instrumentation; the Kubernetes Helm chart enables production-scale deployment with autoscaling
**Depends on**: Phase 7
**Requirements**: SDK-01, SDK-02, DEPLOY-04
**Success Criteria** (what must be TRUE):
  1. A Mesh application can add the Mesher SDK and automatically receive actor crash events in Mesher with full supervision tree context — no manual instrumentation required
  2. The Mesher SDK HTTP middleware instruments request throughput, response time (p50/p95/p99), and error rate without any changes to handler code
  3. A production deployment runs via `helm install mesher` with Horizontal Pod Autoscaler on the ingestion component; all configuration is environment-variable driven
**Plans**: TBD

### Phase 9: AI Features (SaaS Tier)
**Goal**: The SaaS platform provides AI-powered root cause analysis, anomaly detection, alert noise reduction, and a natural-language chat agent grounded in live Mesher data
**Depends on**: Phase 7
**Requirements**: AI-01, AI-02, AI-03, AI-04
**Success Criteria** (what must be TRUE):
  1. When a new issue is created, the SaaS platform automatically runs root cause analysis: the issue detail page shows an LLM-generated summary of the error, probable cause, and suggested fix using stack trace + recent events as context
  2. The SaaS platform surfaces anomaly detection alerts: per-metric and per-error-rate deviations from historical baseline are flagged before they generate user-reported incidents
  3. During a sustained incident, related alerts are grouped into a single notification; low-priority noise is suppressed while the incident is active
  4. A SaaS user can ask natural language questions in the AI chat agent ("show me checkout errors in the last 7 days") and receive answers grounded in live Mesher data via MCP integration
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation + Toolchain Spike | 4/6 | In Progress | - |
| 1.1. ORM Migration (INSERTED) | 4/4 | Complete | 2026-03-03 |
| 1.2. Repo Reorganization (INSERTED) | 3/3 | Complete | 2026-03-04 |
| 2. Error Ingestion Core | 0/TBD | Not started | - |
| 3. Issue Management + REST API | 0/TBD | Not started | - |
| 4. Metrics Ingestion + Dashboards | 0/TBD | Not started | - |
| 5. Real-Time Push | 0/TBD | Not started | - |
| 6. Alerting + Notifications | 0/TBD | Not started | - |
| 7. Frontend Polish + Deployment | 0/TBD | Not started | - |
| 8. SDK + Kubernetes | 0/TBD | Not started | - |
| 9. AI Features (SaaS) | 0/TBD | Not started | - |

# Mesher — v1 Requirements

**Generated:** 2026-03-03
**Status:** Active
**Coverage:** All v1 requirements mapped to phases in ROADMAP.md

---

## v1 Requirements

### AUTH — Authentication & User Accounts

- [x] **AUTH-01**: Self-hosted user can register an account with email and password
- [x] **AUTH-02**: User can log in and maintain session across browser refreshes
- [x] **AUTH-03**: User can log out from any page
- [ ] **AUTH-04**: Self-hosted user can reset their password via email link
- [ ] **AUTH-05**: SaaS user can sign in with Google OAuth (SaaS tier only)

### ORG — Organizations & Projects

- [ ] **ORG-01**: User can create an organization and become its owner
- [ ] **ORG-02**: Organization owner can invite members by email
- [ ] **ORG-03**: Invited user can accept an invitation and join the organization
- [ ] **ORG-04**: User can create a project scoped to their organization
- [ ] **ORG-05**: User can generate and revoke API keys / DSNs per project
- [x] **ORG-06**: Each organization is provisioned with its own PostgreSQL schema at signup (schema-per-org isolation)

### ERR — Error Tracking & Issue Management

- [ ] **ERR-01**: System captures error events with stack traces, message, severity level, exception type, and arbitrary metadata
- [ ] **ERR-02**: System deduplicates events into issues by fingerprint: exception type + normalized top 3–5 application stack frames (line numbers stripped, framework frames excluded)
- [ ] **ERR-03**: User can view the issue list grouped by fingerprint, showing occurrence count per issue
- [ ] **ERR-04**: User can transition an issue through its lifecycle: open → resolved → ignored
- [ ] **ERR-05**: System automatically re-opens a resolved or ignored issue when a new matching event is received
- [ ] **ERR-06**: User can bulk-update issue status (bulk resolve, bulk ignore) from the issue list
- [ ] **ERR-07**: User can filter the issue list by project, severity level, environment, status, and time range
- [ ] **ERR-08**: User can search issues by error message substring
- [ ] **ERR-09**: User can view the error timeline for each issue: first seen timestamp, last seen timestamp, total occurrence count, and an occurrence sparkline
- [ ] **ERR-10**: User can tag inbound events with an environment string (e.g., production, staging, development) and filter the issue list by environment
- [ ] **ERR-11**: New error events are visible in the dashboard within 5 seconds of ingestion (server-sent events push; no polling required)

### INGEST — Ingestion Protocols

- [ ] **INGEST-01**: System accepts error events and trace data via OTLP/HTTP on port 4318 (protobuf primary, JSON fallback)
- [ ] **INGEST-02**: System accepts infrastructure metrics via OTLP/HTTP on port 4318
- [ ] **INGEST-03**: System accepts Sentry SDK events via the Sentry envelope format at `/api/{project_id}/envelope/` — existing Sentry DSN can be pointed at Mesher without SDK code changes
- [ ] **INGEST-04**: System accepts error events and metrics via a generic JSON HTTP REST API for custom integrations
- [ ] **INGEST-05**: All ingest endpoints authenticate requests via project-scoped API key or DSN
- [ ] **INGEST-06**: System enforces per-org ingest rate limits and returns HTTP 429 with a Retry-After header when exceeded
- [ ] **INGEST-07**: System exposes a `/health/ingest` endpoint that reports ingestion pipeline health (healthy / degraded / unavailable)

### METRICS — Infrastructure Metrics Storage

- [ ] **METRICS-01**: System ingests time-series metrics with a fixed schema: CPU usage (%), memory usage (%), request throughput (req/s), response time (p50/p95/p99 ms), error rate (%)
- [ ] **METRICS-02**: System enforces a fixed metric label allowlist at ingestion and rejects events with unknown label keys (HTTP 400)
- [ ] **METRICS-03**: System stores raw metrics in a TimescaleDB hypertable and maintains continuous aggregates at 5-minute and 1-hour rollup intervals
- [ ] **METRICS-04**: System applies a configurable retention policy to raw metrics (default: 90 days; continuous aggregates: 365 days)
- [ ] **METRICS-05**: System derives and exposes capacity/scaling indicators: CPU headroom percentage, memory headroom percentage, and a throughput trend indicator (trending toward limit / stable / declining)

### DASH — Dashboards & Visualization

- [ ] **DASH-01**: User can view a time-series line chart for any infrastructure metric on the project dashboard
- [ ] **DASH-02**: User can view a time-series area chart for any infrastructure metric on the project dashboard
- [ ] **DASH-03**: User can select the dashboard time window from: 1h, 6h, 24h, 7d, 30d
- [ ] **DASH-04**: Dashboard metric charts auto-update in real time via WebSocket push, batched to a maximum of one update per 500ms
- [ ] **DASH-05**: User can view capacity/scaling indicator gauges showing each resource's proximity to its defined limit

### ALERT — Alerting Rules & Evaluation

- [ ] **ALERT-01**: User can define an alert rule on error rate: fires when error rate exceeds a threshold percentage over a configurable time window
- [ ] **ALERT-02**: User can define an alert rule on a metric value: fires when CPU, memory, throughput, response time, or error rate exceeds a threshold for a configurable duration
- [ ] **ALERT-03**: Alert rules support a `for` duration parameter: the condition must hold for N consecutive evaluations before the alert fires
- [ ] **ALERT-04**: Alert evaluation uses a full state machine: inactive → pending → firing → resolved (notifications sent on state transitions only, not on every evaluation)
- [ ] **ALERT-05**: User can configure a per-rule re-notification cooldown to prevent alert storms during sustained incidents

### NOTIF — Notifications

- [ ] **NOTIF-01**: System sends alert notifications via SMTP email on alert state transitions (user-supplied SMTP server)
- [ ] **NOTIF-02**: System sends alert notifications via HTTP webhook on alert state transitions
- [ ] **NOTIF-03**: System sends alert notifications via the Slack API with formatted messages including metric value, threshold, time window, and a direct link to the relevant dashboard
- [ ] **NOTIF-04**: System deduplicates notifications within a configurable dedup window to prevent duplicate delivery during rapid state transitions

### SDK — Native SDKs

- [ ] **SDK-01**: Mesh-native SDK automatically captures actor crash events and reports them to Mesher with full actor supervision tree context
- [ ] **SDK-02**: Mesh-native SDK provides HTTP middleware that auto-instruments request throughput, response time (p50/p95/p99), and error rate without requiring changes to handler code

### DEPLOY — Deployment & Infrastructure

- [x] **DEPLOY-01**: Self-hosted deployment runs with `docker compose up` using a 3-service stack: mesher app, TimescaleDB, Valkey — no additional services required
- [x] **DEPLOY-02**: All runtime configuration is driven by environment variables; no config file is required for a basic deployment
- [x] **DEPLOY-03**: Docker Compose stack includes health checks for all three services and the app waits for database readiness before starting
- [ ] **DEPLOY-04**: Production-scale deployment is supported via a Kubernetes Helm chart with Horizontal Pod Autoscaler on the ingestion component

### AI — AI Features (SaaS Tier Only)

- [ ] **AI-01**: SaaS platform runs AI root cause analysis on newly-created issues: an LLM summarizes the error, identifies the probable cause, and suggests a fix, using the stack trace + recent events + similar historical issues as context
- [ ] **AI-02**: SaaS platform provides anomaly detection: establishes per-metric and per-error-rate baselines from historical data and surfaces deviations before they become user-reported incidents
- [ ] **AI-03**: SaaS platform provides AI-powered alerting noise reduction: correlates related alerts during incidents into a single grouped notification and suppresses low-priority noise while an incident is active
- [ ] **AI-04**: SaaS platform provides an in-app AI chat agent with MCP integration: users can ask natural language questions ("show me all checkout errors in the last 7 days", "are there any memory leaks trending upward?") and receive answers grounded in live Mesher data

---

## v2 / Future Requirements

These are deferred — not in v1 scope but not permanently excluded.

### Error Tracking (v1.x / v2)
- Custom fingerprint rules via the UI — add in v1.x after core grouping is proven
- Distributed tracing / APM span visualization — v2 only; major separate product surface

### Auth (v2)
- Fine-grained RBAC — v2; admin/member roles are sufficient for v1
- SSO / SAML / OIDC — SaaS enterprise tier only; v2

### Notifications (v1.x)
- GitHub issue creation from alert rules
- Jira ticket creation from alert rules

### Collaboration (v2)
- Issue comments and @mentions — social layer; build after core UX is excellent

### Metrics (v2)
- Custom user-defined metrics — fixed schema in v1; custom in v2 with strict cardinality limits enforced at ingestion

---

## Out of Scope

These are **explicitly excluded** from Mesher. Reasons are provided to prevent re-adding in future sessions.

| Feature | Reason |
|---------|--------|
| Distributed tracing / APM spans | Separate product surface — trace storage, UI waterfall, context propagation each require full product effort. Correlate errors to request IDs via metadata in v1. |
| Log management pipeline | Different product category with different storage and query requirements. GlitchTip tried this and deprecated it. Point users to Loki/Grafana for logs. |
| Session replay / RUM | Browser SDK complexity + PII compliance + replay player UI = multi-month effort. Server-side only. Highlight.io built this and was acquired out of viability. |
| Synthetic monitoring / uptime checks | Proactive polling product (separate from reactive SDK-push monitoring). GlitchTip added this feature and stopped maintaining it. |
| Native mobile SDKs (iOS/Android) | Requires crash signal handling, dSYM symbol upload/processing, Bitcode support, ANR detection — months of platform-specific work. |
| Custom metrics (v1) | Cardinality explosion risk. Fixed schema sufficient for all v1 use cases. Retrofitting cardinality controls requires dropping and recreating hypertables. |
| ClickHouse as storage backend | Defeats self-hosted simplicity pitch. TimescaleDB sufficient at self-hosted scale. ClickHouse adds 8GB+ RAM requirement and ops overhead. |
| Email-as-primary-UX | Unbounded email volume + deliverability complexity. Digest/threshold alerts only. Users manage their error queue in the UI. |
| Fine-grained RBAC (v1) | Admin/member roles are sufficient. Role explosion and permission matrices create heavy admin surface. Add roles when enterprise compliance requires it. |
| SSO / SAML (v1) | SaaS enterprise tier only. Auth provider integrations have many edge cases. Deferred to v2. |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 1 | Complete |
| AUTH-02 | Phase 1 | Complete |
| AUTH-03 | Phase 1 | Complete |
| AUTH-04 | Phase 1 | Pending |
| AUTH-05 | Phase 1 | Pending |
| ORG-01 | Phase 1 | Pending |
| ORG-02 | Phase 1 | Pending |
| ORG-03 | Phase 1 | Pending |
| ORG-04 | Phase 1 | Pending |
| ORG-05 | Phase 1 | Pending |
| ORG-06 | Phase 1 | Complete |
| DEPLOY-01 | Phase 1 | Complete |
| DEPLOY-02 | Phase 1 | Complete |
| DEPLOY-03 | Phase 1 | Complete |
| INGEST-01 | Phase 2 | Pending |
| INGEST-02 | Phase 2 | Pending |
| INGEST-03 | Phase 2 | Pending |
| INGEST-04 | Phase 2 | Pending |
| INGEST-05 | Phase 2 | Pending |
| INGEST-06 | Phase 2 | Pending |
| INGEST-07 | Phase 2 | Pending |
| ERR-01 | Phase 2 | Pending |
| ERR-02 | Phase 2 | Pending |
| ERR-10 | Phase 2 | Pending |
| ERR-03 | Phase 3 | Pending |
| ERR-04 | Phase 3 | Pending |
| ERR-05 | Phase 3 | Pending |
| ERR-06 | Phase 3 | Pending |
| ERR-07 | Phase 3 | Pending |
| ERR-08 | Phase 3 | Pending |
| ERR-09 | Phase 3 | Pending |
| METRICS-01 | Phase 4 | Pending |
| METRICS-02 | Phase 4 | Pending |
| METRICS-03 | Phase 4 | Pending |
| METRICS-04 | Phase 4 | Pending |
| METRICS-05 | Phase 4 | Pending |
| DASH-01 | Phase 4 | Pending |
| DASH-02 | Phase 4 | Pending |
| DASH-03 | Phase 4 | Pending |
| DASH-05 | Phase 4 | Pending |
| ERR-11 | Phase 5 | Pending |
| DASH-04 | Phase 5 | Pending |
| ALERT-01 | Phase 6 | Pending |
| ALERT-02 | Phase 6 | Pending |
| ALERT-03 | Phase 6 | Pending |
| ALERT-04 | Phase 6 | Pending |
| ALERT-05 | Phase 6 | Pending |
| NOTIF-01 | Phase 6 | Pending |
| NOTIF-02 | Phase 6 | Pending |
| NOTIF-03 | Phase 6 | Pending |
| NOTIF-04 | Phase 6 | Pending |
| SDK-01 | Phase 8 | Pending |
| SDK-02 | Phase 8 | Pending |
| DEPLOY-04 | Phase 8 | Pending |
| AI-01 | Phase 9 | Pending |
| AI-02 | Phase 9 | Pending |
| AI-03 | Phase 9 | Pending |
| AI-04 | Phase 9 | Pending |

*Traceability filled by gsd-roadmapper — 2026-03-03*

---

*Last updated: 2026-03-03 after roadmap creation*

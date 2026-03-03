# Mesher

## What This Is

Mesher is an open-source application observability platform — a self-hostable alternative to Sentry and Datadog. It captures errors with advanced filtering and aggregation, and collects infrastructure metrics (throughput, capacity, scaling indicators) so teams can monitor and act on production issues. A hosted SaaS version adds AI-powered features including root cause analysis, anomaly detection, and an in-app AI chat agent.

## Core Value

The easiest way to add full-stack observability (errors + infrastructure metrics) to any service — deployed with a single Docker Compose command, built natively for Mesh apps.

## Requirements

### Validated

(None yet — ship to validate)

### Active

**Error Tracking**
- [ ] Capture error events with stack traces, message, level, and metadata
- [ ] Group duplicate errors into issues (deduplication by fingerprint)
- [ ] Advanced filtering: by project, severity, environment, time range, tags, status
- [ ] Issue lifecycle: open → resolved → ignored (with re-open on recurrence)
- [ ] Error timeline view: first seen, last seen, occurrence frequency
- [ ] Environment tagging: production / staging / development

**Infrastructure Metrics**
- [ ] Ingest time-series metrics: CPU, memory, request throughput, response time, error rate
- [ ] Real-time dashboards with line, area, and heatmap charts
- [ ] Historical trend views with configurable time windows
- [ ] Capacity / scaling indicators to identify when to scale

**Ingestion**
- [ ] OTLP-compatible HTTP ingestion endpoint (errors and metrics)
- [ ] Mesh native SDK: actor crash reports + HTTP middleware auto-instrumentation
- [ ] Generic HTTP API for custom integrations

**Alerting**
- [ ] Define alert rules on metric thresholds or error rates
- [ ] Notification channels: email, webhook

**Auth & Multi-tenancy**
- [ ] User accounts and organizations
- [ ] Projects scoped to organizations
- [ ] Schema-per-org data isolation
- [ ] API key authentication for SDKs

**Deployment**
- [ ] Docker Compose stack (self-hosted, one-command)
- [ ] Kubernetes Helm chart for production-scale deployments
- [ ] Environment-variable-driven configuration

**SaaS Extras (hosted only)**
- [ ] AI root cause analysis: LLM explains errors and suggests fixes
- [ ] Anomaly detection: ML flags unusual patterns before they become incidents
- [ ] AI-powered alerting: smart grouping, noise reduction
- [ ] In-app AI chat agent with MCP integration (e.g., "show me issues from the last 7 days")

### Out of Scope

- Browser / RUM SDK — error tracking is server-side first
- Native mobile SDKs — not in scope for v1
- Log management pipeline — separate from error tracking, deferred
- Synthetic monitoring / uptime checks — future milestone
- Real-time collaboration / comments on issues — v2

## Context

Built entirely on three proprietary tools in active beta development:

1. **Mesh** (v12.0) — Backend language. Elixir-style syntax, static type inference, actor model, LLVM native binaries. Built-in HTTP server, WebSockets, PostgreSQL/SQLite drivers, Crypto, JSON, DateTime stdlib. Source of truth: GitNexus `mesh` repo.

2. **Streem-2** — Frontend framework. Reactive signals + JSX (SolidJS-style). `signal()`, `computed()`, `effect()`. Built-in WebSocket/SSE stream adapters (`fromWebSocket`, `fromSSE`). Lit custom element interop. Source of truth: GitNexus `streem-2` repo.

3. **LitUI (lit-components)** — Component library. Lit web components + Tailwind CSS v4. Available: button, charts (line, area, heatmap), data-table, dialog, input, select, tabs, toast, tooltip, accordion, date-picker, time-picker, and more. Source of truth: GitNexus `lit-components` repo.

**Database:** PostgreSQL + TimescaleDB extension for time-series metrics.

**Beta Toolchain Protocol:** All three tools are in beta. When a limitation, missing feature, or bug is encountered in Mesh, Streem-2, or LitUI, work MUST STOP and the issue must be surfaced to the user explicitly with:
- Which tool is affected
- What the limitation is
- What was being attempted
The user will patch the tool and return to resume. Do not work around tool bugs.

## Constraints

- **Tech Stack**: Mesh backend, Streem-2 frontend, LitUI components — no substitutions
- **Beta Tools**: Mesh, Streem-2, and LitUI are all in beta; bugs will occur and must be escalated
- **Source of Truth**: Use GitNexus MCP for all questions about Mesh, Streem-2, and LitUI capabilities
- **Database**: PostgreSQL + TimescaleDB (Mesh has built-in PG driver; TimescaleDB runs as a PG extension)
- **Multi-tenancy**: Schema-per-org isolation in PostgreSQL
- **Open Source**: Core product is MIT licensed; SaaS extras are proprietary/optional
- **Deployment**: Self-hosted must work with Docker Compose; production must support Kubernetes

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| PostgreSQL + TimescaleDB over ClickHouse | Avoids adding ClickHouse as a dependency; Mesh has native PG support; TimescaleDB provides time-series perf as a PG extension | — Pending |
| Schema-per-org isolation | Strong data isolation for SaaS, reasonable migration overhead vs per-DB isolation | — Pending |
| OTLP as primary ingestion protocol | Industry standard; any language/framework can send data in; no vendor lock-in | — Pending |
| Mesh actor model for ingestion pipeline | Natural fit for high-throughput event processing; supervisor trees for reliability | — Pending |
| Open-source core + proprietary SaaS extras | Drives adoption while sustaining commercial development | — Pending |

---
*Last updated: 2026-03-03 after initialization*

# Feature Research

**Domain:** Self-hosted application observability platform (error tracking + infrastructure metrics)
**Researched:** 2026-03-03
**Confidence:** MEDIUM-HIGH (WebSearch verified against multiple credible sources; official Sentry docs and competitor analysis cross-referenced)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete or disqualifies Mesher as a Sentry replacement.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Error capture with stack traces | Core reason to adopt error tracking | LOW | Message, level, exception type, file/line, in-app frame detection |
| Issue deduplication by fingerprint | Without this, noise makes the tool unusable | MEDIUM | Hash on: project + error type + message + file + line. Sentry's algorithm is the reference. Custom fingerprint rules (server-side) needed in v1. |
| Issue lifecycle management | Users need to manage their queue | LOW | States: open → resolved → ignored → re-opened on recurrence. Bulk actions mandatory. |
| Issue list with filtering | Core UX loop: see what's broken, filter to relevant | MEDIUM | Filter by: project, severity, environment, time range, status, tags. Search by message. |
| Error timeline (first seen / last seen / occurrence count) | Every Sentry user expects this | LOW | "First seen 3 days ago, last seen 5 minutes ago, 847 occurrences" pattern |
| Environment tagging | Separating production from staging noise | LOW | Tag events with environment string on ingest. Filter issues by environment. |
| Real-time error ingestion | "Is this live?" — users expect near-instant | LOW | Sub-5s latency from SDK send to dashboard visibility. |
| API key auth for SDKs | How SDKs identify themselves | LOW | Project-scoped DSN keys. Sentry DSN format expected for compatibility. |
| Multi-project support | Any team with multiple services needs this | LOW | Org scoped projects. Cross-project issue list optional in v1. |
| Alerting on error rate thresholds | "Tell me when things break" | MEDIUM | Rule: if error rate > N in time window, fire notification. Email + webhook minimum. |
| Infrastructure metrics ingestion | Required for Datadog-competitive story | MEDIUM | CPU, memory, request throughput, response time, error rate as time-series |
| Time-series dashboards | Visualize infrastructure metrics | MEDIUM | Line and area charts minimum. Configurable time windows (1h, 6h, 24h, 7d, 30d). |
| Self-hosted single-command deployment | The #1 pitch — without this the product has no identity | LOW | Docker Compose stack. Users expect `docker compose up` and it works. |
| User accounts and organization management | Multi-user product requires auth | LOW | Signup, login, org creation, invite members. |
| OTLP-compatible ingestion endpoint | Industry standard; any SDK can send | MEDIUM | Sentry SDK compat for errors is also required (see differentiators) |

**Sources:** [Sentry Issue Grouping Docs](https://docs.sentry.io/concepts/data-management/event-grouping/), [Migration from Sentry research](https://www.bugsink.com/tired-of-self-hosting-sentry-try-bugsink/), [Minimum viable features analysis](https://betterstack.com/community/comparisons/sentry-alternatives/), [DevOps dashboard best practices](https://middleware.io/blog/devops-metrics-you-should-be-monitoring/)

---

### Differentiators (Competitive Advantage)

Features that set Mesher apart. Not universally expected, but create real switching value and retention.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Sentry SDK drop-in compatibility | Users can migrate in minutes without changing instrumentation code | MEDIUM | Accept Sentry's envelope format and DSN at `/api/{project_id}/envelope/`. GlitchTip and Bugsink both do this. Critical differentiator vs. custom-format-only tools. |
| Lean self-hosted architecture (PostgreSQL + TimescaleDB only) | The #1 complaint about self-hosted Sentry is its 16+ container stack requiring 16GB RAM. Mesher runs on a $10/month VPS. | LOW | No ClickHouse. No Kafka. No Snuba. No Relay. No Symbolicator. Postgres + TimescaleDB = sufficient for most self-hosted scale. This is a positioning statement, not just an architecture choice. |
| Combined error + metrics in one tool | Eliminates the Sentry + Prometheus + Grafana trifecta | HIGH | Sentry has no infra metrics. Signoz has metrics but no dedicated error grouping UI. Mesher occupies the gap. |
| Capacity / scaling indicators | Tell users when to scale, not just what's broken | MEDIUM | Derived metrics: requests/CPU trending toward limit, memory headroom, error rate percentile alerts. Most lean tools skip this. |
| AI root cause analysis (SaaS tier) | LLM explains what the error means and suggests fixes | HIGH | SaaS-only. Context: stack trace + recent events + similar historical issues. OpenAI / Anthropic API call. Do not attempt on-prem LLM in v1. |
| Anomaly detection (SaaS tier) | Flags unusual patterns before they become incidents | HIGH | SaaS-only. Statistical baseline per metric/error-rate, deviation alert. ML-powered. Flag for deeper research in phase. |
| In-app AI chat agent (SaaS tier) | "Show me issues from the last 7 days affecting checkout" — natural language over your own data | HIGH | SaaS-only. MCP integration. Requires mature data model before this is useful. Defer to v2 unless data model is clean. |
| Mesh-native SDK | First-class actor crash reporting and HTTP middleware auto-instrumentation for Mesh apps | MEDIUM | Unique to Mesher. No other tool supports Mesh natively. Positioning for Mesh ecosystem. |
| AI-powered alerting noise reduction (SaaS tier) | Smart grouping to reduce alert fatigue | HIGH | SaaS-only. Industry pain point: alert storms overwhelm teams. Topological correlation (Datadog's 2025 feature) is the reference implementation. |
| Schema-per-org data isolation | Strong compliance story for regulated industries | MEDIUM | PostgreSQL schema isolation per org. HIPAA/GDPR positioning. Signoz and GlitchTip don't offer this. |
| Kubernetes Helm chart | Production-scale self-hosted deployment | MEDIUM | Docker Compose is for single-node. Helm enables HA. Most lean alternatives skip this. Differentiator for engineering-mature teams. |

**Sources:** [Sentry self-hosted complaints HN thread](https://news.ycombinator.com/item?id=43725815), [GlitchTip vs Sentry vs Bugsink analysis](https://www.bugsink.com/blog/glitchtip-vs-sentry-vs-bugsink/), [Datadog 2025 DASH features](https://www.datadoghq.com/blog/dash-2025-new-feature-roundup-observe/), [AI observability tools 2026](https://www.dash0.com/comparisons/ai-powered-observability-tools)

---

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem reasonable but create scope creep, architectural debt, or maintenance burden that will kill a lean self-hosted product.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Distributed tracing / APM spans | Sentry has it; users will ask for it | Requires trace storage schema, UI waterfall visualization, context propagation, and sampling strategy — each is its own product surface. Signoz was built around this and still has missing spans bugs. In v1, this is a rewrite-trigger. | Correlate errors to request IDs via metadata. Provide OTLP trace endpoint for forwarding to Tempo/Jaeger externally. Add tracing visualization in v2. |
| Log management pipeline | "Can I ship logs here too?" | Log ingestion at volume requires completely different storage patterns, retention policies, and query interfaces. GlitchTip tried to do this and deprecated the feature. Signoz added logs but it's clunky. | Stay focused on structured error events and time-series metrics. Point users to Loki/Grafana for logs. |
| Session replay / RUM | Sentry has it; frontend developers love it | Browser SDK complexity, replay storage costs, privacy compliance (PII in session recordings), and replay player UI are each major features. Highlight.io built its entire product around this and still got acquired out of viability. | Out of scope v1 explicitly. Server-side error tracking only. |
| Real-time collaboration on issues | "Can I comment on this issue?" | Builds notification plumbing, comment threading, @mention, activity feeds. Doubles the complexity of the issue system. | Use integrated Slack/Jira actions instead. Resolve issues in your existing tools. Comments in v2 only. |
| Synthetic monitoring / uptime checks | "Ping my endpoint every 60s" | Requires distributed probes, geographic coverage, certificate expiry, DNS monitoring — a separate product category entirely. GlitchTip added uptime monitoring and stopped maintaining it. | Out of scope v1. Focus on reactive (SDK-push) monitoring, not proactive polling. |
| Native mobile SDKs (iOS/Android) | Mobile teams want crash reporting | Mobile SDK requires crash signal handling, dSYM symbol upload/processing (Symbolicator equivalent), Bitcode support, ANR detection. This is months of platform-specific work. | Server-side only. Mobile teams can send custom events via HTTP API. |
| Custom metrics (user-defined) | "Track my business metrics here too" | Custom metric schemas, cardinality explosion, retention policies per metric type, and query-builder UI complexity mushroom. Datadog charges extra for custom metrics specifically because of this. | Fixed schema metrics in v1: CPU, memory, throughput, response time, error rate. Custom metrics in v2 as named scalar time-series with defined cardinality limits. |
| ClickHouse as storage backend | "Isn't Postgres too slow for time-series?" | ClickHouse is a correct answer for high-cardinality OLAP at Sentry/Signoz scale, but adds ops complexity that defeats Mesher's core pitch. TimescaleDB with proper continuous aggregates handles most self-hosted scale. | TimescaleDB on PostgreSQL. If scale demands ClickHouse, that's a v3 architecture decision. Flag this as a risk, not a v1 decision. |
| RBAC with fine-grained permissions | Enterprise teams always want granular roles | Role explosion, permission matrices, UI for managing permissions. Heavy admin surface. Signoz and GlitchTip both get complaints about this. | Two roles in v1: admin and member. Organization owner. API keys for SDKs. Fine-grained RBAC in v2. |
| SSO / SAML / OIDC | Enterprise compliance teams require it | Auth provider integrations, token refresh flows, SCIM provisioning. Each IdP has quirks. Signoz's SSO bugs crashed their community edition. | Username + password in v1. Consider OAuth (GitHub, Google) as a low-complexity step up. SAML for SaaS tier only in v2. |
| Email-as-primary-UX | "Send me every error via email" | Unbounded email volume, unsubscribe flows, bounce handling, deliverability — becomes a product category. | Digest email alerts on rules only. No per-event email. Users manage their queue in the UI. |

**Sources:** [Signoz problems 2025](https://knowledgebase.signoz.io/kb/t/understanding-signoz-pricing-structure-and-self-hosted-limitations/2K5f67), [GlitchTip missing features](https://www.bugsink.com/blog/glitchtip-vs-sentry-vs-bugsink/), [Highlight.io shutdown](https://www.bugsink.com/a-self-hosted-alternative-to-highlight-io/), [Sentry self-hosted HN complaints](https://news.ycombinator.com/item?id=43725815)

---

## Feature Dependencies

```
[User Accounts + Auth]
    └──requires──> [Organizations]
                       └──requires──> [Projects]
                                          └──requires──> [API Key / DSN auth]
                                                             └──requires──> [Error Ingestion Endpoint]
                                                                                └──enables──> [Issue Grouping]
                                                                                                  └──enables──> [Issue Lifecycle]
                                                                                                                    └──enables──> [Alerting]

[Error Ingestion Endpoint]
    └──requires──> [OTLP endpoint] (for generic clients)
    └──requires──> [Sentry envelope endpoint] (for Sentry SDK compat)

[Metrics Ingestion]
    └──requires──> [TimescaleDB schema]
                       └──enables──> [Time-series dashboards]
                                         └──enables──> [Metric threshold alerting]
                                                           └──enables──> [Capacity indicators]

[Alerting]
    └──requires──> [Issue Grouping] (error alerts)
    └──requires──> [Metrics Ingestion] (infra alerts)
    └──requires──> [Notification channels] (email + webhook)

[AI Root Cause Analysis] (SaaS only)
    └──requires──> [Issue Grouping]
    └──requires──> [LLM API integration]
    └──requires──> [Mature error data model with metadata]

[Anomaly Detection] (SaaS only)
    └──requires──> [Metrics Ingestion]
    └──requires──> [Baseline computation] (needs weeks of data)
    └──enhances──> [Alerting]

[AI Chat Agent] (SaaS only)
    └──requires──> [Anomaly Detection]
    └──requires──> [AI Root Cause Analysis]
    └──requires──> [Mature, stable data model]
    → Defer to v2

[Kubernetes Helm Chart]
    └──requires──> [Docker Compose stack working] (validate config first)
```

### Dependency Notes

- **Issue Grouping requires Error Ingestion:** Cannot group what you cannot receive. Ingestion pipeline must be solid before building grouping logic.
- **Alerting requires both error and metrics subsystems:** Alerts on metrics and alerts on error rates are separate rule types. Build them independently but surface them in a unified alert rules UI.
- **AI features require mature data model:** Building AI root cause analysis before the error schema is stable means rebuilding the LLM prompts every schema migration. AI features should be the last subsystem added, not first.
- **Anomaly detection requires baseline data:** Statistical anomaly detection requires weeks of data to establish normal baselines. Cannot launch this feature on day one of a fresh installation — onboarding flow must explain this lag.
- **Sentry SDK compat requires envelope endpoint:** The Sentry SDK POSTs to `/api/{project_id}/envelope/` with a specific multipart format. Building a standard OTLP endpoint alone does not give SDK compat. Both endpoints are required for migration story.

---

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed for a team to replace self-hosted Sentry and add basic infra metrics.

- [ ] **Error ingestion (Sentry envelope format + OTLP)** — Without this, nobody can send data. Both formats are required for migration story.
- [ ] **Issue deduplication by fingerprint** — Without this, users drown in duplicate events and abandon the tool.
- [ ] **Issue lifecycle (open/resolved/ignored + auto-reopen)** — Without this, users cannot manage their error queue.
- [ ] **Issue list with filtering (project, environment, status, time range)** — Without this, the dashboard is unusable at scale.
- [ ] **Error timeline (first seen, last seen, occurrence count, sparkline)** — Visual noise reduction. Users need to prioritize.
- [ ] **Environment tagging** — Separating production from staging is a day-one need.
- [ ] **Multi-project, multi-org support** — Any team with more than one service needs this immediately.
- [ ] **API key / DSN auth** — Required for SDK authentication.
- [ ] **Infrastructure metrics ingestion (CPU, memory, throughput, response time, error rate)** — Core Datadog-competitive story. Fixed schema in v1.
- [ ] **Time-series dashboards (line + area charts, configurable windows)** — Visualize the metrics that were ingested. Useless without this.
- [ ] **Alert rules on error rate and metric thresholds** — Tell users when things break. Email + webhook channels.
- [ ] **User accounts + organizations + invite flow** — Multi-user product requires auth from day one.
- [ ] **Docker Compose self-hosted deployment** — The core product promise. Must work out of the box.

### Add After Validation (v1.x)

Features to add once the core error+metrics loop is working and users are active.

- [ ] **Capacity / scaling indicators** — Derived from metrics. Add when users ask "should I scale?" — trigger: first user complaint about not knowing when to scale.
- [ ] **Kubernetes Helm chart** — Add when first enterprise/team user needs production HA deployment. Trigger: first GitHub issue asking for it.
- [ ] **Slack notification channel** — High-value, low-complexity addition to alerting. Trigger: after email + webhook are stable.
- [ ] **AI root cause analysis (SaaS tier)** — Add when error schema is stable and SaaS launch is planned. Do not build before data model is proven.
- [ ] **Anomaly detection (SaaS tier)** — Add after AI RCA is working. Requires baseline data accumulation logic.
- [ ] **GitHub / Jira alert actions** — Create issue in GitHub/Jira from alert rule. Useful for teams with existing workflows.

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **AI chat agent (MCP integration)** — Requires mature, stable data model + AI RCA + anomaly detection all working. Genuine AI-as-interface requires all underlying data to be clean. Defer entirely to v2.
- [ ] **Distributed tracing visualization** — Huge build. Trace storage, UI waterfall, context propagation. Add only if users strongly request and are willing to pay.
- [ ] **Fine-grained RBAC** — Two roles (admin/member) is sufficient for v1. Add roles when enterprises with compliance requirements adopt the product.
- [ ] **SSO / SAML** — SaaS-tier only. Add when enterprise deals require it.
- [ ] **Custom metrics (user-defined)** — Add after fixed-schema metrics are stable and users ask for extensibility.
- [ ] **Issue comments / collaboration** — Social layer on top of debugging. Defer until core experience is excellent.
- [ ] **Session replay / RUM** — Out of scope. Server-side first. Revisit if product pivots to full frontend observability.
- [ ] **Log management** — Out of scope. Different product category. Do not let feature requests pull Mesher into log pipelines.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Error ingestion (Sentry envelope + OTLP) | HIGH | MEDIUM | P1 |
| Issue deduplication by fingerprint | HIGH | MEDIUM | P1 |
| Issue lifecycle (open/resolved/ignored) | HIGH | LOW | P1 |
| Issue list with filtering | HIGH | MEDIUM | P1 |
| Environment tagging | HIGH | LOW | P1 |
| Multi-project / multi-org | HIGH | LOW | P1 |
| API key / DSN auth | HIGH | LOW | P1 |
| Metrics ingestion (fixed schema) | HIGH | MEDIUM | P1 |
| Time-series dashboards | HIGH | MEDIUM | P1 |
| Alert rules + email/webhook | HIGH | MEDIUM | P1 |
| User accounts + org auth | HIGH | LOW | P1 |
| Docker Compose deployment | HIGH | LOW | P1 |
| Error timeline (first/last seen, count) | MEDIUM | LOW | P1 |
| Capacity / scaling indicators | MEDIUM | MEDIUM | P2 |
| Kubernetes Helm chart | MEDIUM | MEDIUM | P2 |
| Slack notification channel | MEDIUM | LOW | P2 |
| AI root cause analysis (SaaS) | HIGH | HIGH | P2 |
| Anomaly detection (SaaS) | HIGH | HIGH | P2 |
| GitHub / Jira alert actions | MEDIUM | MEDIUM | P2 |
| AI chat agent (SaaS) | HIGH | HIGH | P3 |
| Distributed tracing visualization | MEDIUM | HIGH | P3 |
| Fine-grained RBAC | LOW | HIGH | P3 |
| SSO / SAML | LOW | HIGH | P3 |
| Custom metrics | MEDIUM | HIGH | P3 |
| Issue comments | LOW | MEDIUM | P3 |
| Session replay | LOW | HIGH | P3 |
| Log management | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible (v1.x)
- P3: Nice to have, future consideration (v2+)

---

## Competitor Feature Analysis

| Feature | Sentry (self-hosted) | Signoz (self-hosted) | GlitchTip (self-hosted) | Mesher (v1 target) |
|---------|----------------------|---------------------|------------------------|-------------------|
| Error tracking + issue grouping | Yes (excellent) | Partial (basic) | Yes (good) | Yes |
| Infrastructure metrics | No | Yes (via OTel) | No | Yes |
| Time-series dashboards | No | Yes | No | Yes |
| Distributed tracing / APM | Yes | Yes (core feature) | No | No (v2) |
| Session replay | Yes | No | No | No (out of scope) |
| Log management | No | Yes | No | No (out of scope) |
| Sentry SDK drop-in compat | N/A | No | Yes | Yes |
| OTLP ingestion | Partial | Yes | No | Yes |
| AI root cause analysis | Seer (cloud) | No | No | SaaS tier |
| Anomaly detection | Yes (cloud) | No | No | SaaS tier |
| Self-hosted simplicity | Poor (16+ containers, 16GB RAM) | Poor (ClickHouse + OTel collector complexity) | Good (4 containers) | Target: excellent (Docker Compose, PG+Timescale) |
| Alerting | Yes (complex) | Yes (clunky UI) | Yes (basic) | Yes (threshold rules) |
| Kubernetes support | Yes (complex) | Yes | Limited | v1.x (Helm chart) |
| Multi-org / multi-project | Yes | Yes | Yes | Yes |
| Data ownership | Partial (Fair Source) | Yes (open-source) | Yes (open-source) | Yes (MIT core) |

### What Signoz Gets Wrong (Self-Hosted)

- ClickHouse as a required dependency makes single-node deployment expensive (dedicated CPU, 8GB+ RAM for ClickHouse alone)
- Port conflicts between the SigNoz collector and standalone OTel collectors confuse users
- Empty dashboards after fresh install (data arrives in ClickHouse but UI shows nothing) — trust-destroying UX failure
- Enterprise features (SSO, SAML) locked to Cloud tier, surprising self-hosted users
- Community edition includes Enterprise code that crashes on Google OAuth in air-gapped environments
- High memory usage under load (OTel collector spikes to 10GB+ when pod labels are included)

### What GlitchTip Gets Wrong

- No infrastructure metrics — error-only tool in a world where teams want combined error + infra visibility
- Uptime monitoring feature added then abandoned — signals project scope fragmentation
- UI puts runtime info before the stack trace — debugging data is not front and center
- Smaller community means fewer integrations, fewer SDK examples
- No AI features, no anomaly detection, no growth path beyond basic error tracking

### What Self-Hosted Sentry Gets Wrong

- 16+ Docker containers, 16GB RAM minimum — defeats the purpose of self-hosting for most teams
- Silent event loss when any component in the Kafka → Snuba → ClickHouse pipeline fails — users see empty dashboards with no error
- ClickHouse/Snuba migration bugs that cause stuck state requiring manual intervention
- No official support — teams are on their own when things break
- Sentry's own CEO discourages self-hosting; the product is not designed for it
- Borked releases that require waiting for patch releases

### What Mesher Must Do Better

1. **Reliable ingestion with visible failure modes** — if an event is lost, the user must know why, not see an empty dashboard
2. **Sub-5 container self-hosted deployment** — PostgreSQL + TimescaleDB + app + worker. That is it.
3. **Error + metrics in one tool** — fill the gap between Sentry (errors only) and Signoz (metrics-heavy, weak errors)
4. **Sentry SDK migration path** — users can redirect their existing DSN and be migrated in under 10 minutes
5. **Honest feature scope** — do fewer things excellently, not many things badly

---

## Sources

- [Sentry Issue Grouping Documentation](https://docs.sentry.io/concepts/data-management/event-grouping/) — MEDIUM confidence (official docs, current)
- [Sentry Fingerprint Rules](https://docs.sentry.io/concepts/data-management/event-grouping/fingerprint-rules/) — MEDIUM confidence (official docs)
- [GlitchTip vs Sentry vs Bugsink comparison](https://www.bugsink.com/blog/glitchtip-vs-sentry-vs-bugsink/) — MEDIUM confidence (competitor analysis, single source)
- [Tired of self-hosting Sentry? Bugsink](https://www.bugsink.com/tired-of-self-hosting-sentry-try-bugsink/) — MEDIUM confidence (biased source but factual complaints)
- [I gave up on self-hosted Sentry — HN thread](https://news.ycombinator.com/item?id=43725815) — MEDIUM confidence (community, multiple voices)
- [SigNoz vs Sentry comparison — CubeAPM](https://cubeapm.com/blog/signoz-vs-sentry-vs-cubeapm/) — MEDIUM confidence (competitor blog, cross-referenced)
- [Top Sentry alternatives 2026 — SigNoz](https://signoz.io/comparisons/sentry-alternatives/) — LOW confidence (biased source, SigNoz marketing)
- [Highlight.io shutdown notice](https://www.bugsink.com/a-self-hosted-alternative-to-highlight-io/) — MEDIUM confidence (verifiable fact)
- [SigNoz self-hosted limitations knowledge base](https://knowledgebase.signoz.io/kb/t/understanding-signoz-pricing-structure-and-self-hosted-limitations/2K5f67) — MEDIUM confidence (official SigNoz, biased framing)
- [Datadog DASH 2025 feature roundup](https://www.datadoghq.com/blog/dash-2025-new-feature-roundup-observe/) — HIGH confidence (official Datadog blog)
- [AI observability tools 2026 — Dash0](https://www.dash0.com/comparisons/ai-powered-observability-tools) — LOW confidence (competitor marketing)
- [DevOps metrics 2025 — Middleware](https://middleware.io/blog/devops-metrics-you-should-be-monitoring/) — LOW confidence (single source)
- [Infrastructure monitoring best practices — MOSS](https://moss.sh/devops-monitoring/infrastructure-monitoring-best-practices/) — LOW confidence (single source)

---

*Feature research for: self-hosted observability platform (error tracking + infrastructure metrics)*
*Researched: 2026-03-03*

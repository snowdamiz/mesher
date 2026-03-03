# Phase 1: Foundation + Toolchain Spike - Context

**Gathered:** 2026-03-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can create accounts, form organizations, and deploy the stack locally — while every critical beta toolchain capability (Mesh, Streem-2, LitUI) is proven before any production code is written. Login/auth UI, org/project management, Docker Compose stack, and four toolchain spike tests are all in scope. Error ingestion, metrics, and dashboards are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Auth flow — SaaS vs self-hosted split
- **SaaS**: Google OAuth only — single button, no email/password form, no tabs needed
- **Self-hosted (OSS)**: Email + password only — no OAuth, no third-party dependencies
- Registration form fields (OSS): email + password only (no name field)
- Post-login landing: org setup wizard (first visit); subsequent logins land on org settings

### Auth flow — password reset (OSS only)
- Email link with time-limited token (expires 1 hour)
- Standard forgot-password flow: enter email → receive link → click → set new password

### SaaS tier gating
- Runtime env var: `MESHER_TIER=oss` (default) or `MESHER_TIER=saas`
- Docker Compose defaults to `oss`; SaaS deployment sets `saas`
- SaaS-only features accessed from an OSS instance: return HTTP 403 with a "SaaS only" message
- SaaS Google OAuth: first sign-in auto-creates account and logs in (no separate registration step)

### Invite flow
- Mechanism: email invite for both SaaS and OSS (consistent with existing SMTP dependency for password reset)
- Owner enters email in org settings → system sends invite email with time-limited accept link
- Invitee without an account: clicking invite link → registration form → auto-join org after registration
- Invitee with an existing account: clicking invite link → auto-join immediately (no re-login needed)
- Invite validity: 7 days
- Owner can revoke pending invites from org settings (pending invite list shown)

### Toolchain spikes
- Location: `spikes/` directory at repo root (separate from production code, deletable after Phase 1)
- Format: test files runnable with the project's test runner
- The four spikes required (from success criteria):
  1. **Mesh WebSocket actor supervision** — actor crash under WebSocket load is caught and restarted by supervisor
  2. **PG transaction pooling with SET LOCAL** — schema-per-org SET LOCAL search_path works correctly under a pooled connection
  3. **Streem-2 fromWebSocket() reconnection** — server drops connection; client auto-reconnects within 5 seconds without page reload
  4. **LitUI chart live-update performance** — chart sustains 60fps during continuous live data updates

### Claude's Discretion
- Session storage mechanism (JWT vs Valkey-backed sessions)
- Schema migration strategy for per-org schemas
- Docker Compose service names, port assignments, volume naming
- Exact invite email copy and templates
- Error state UX on auth forms (where and how errors display)

</decisions>

<specifics>
## Specific Ideas

- SaaS login page = single Google button, no form. Intentionally minimal.
- OSS login page = email/password form only. Clean split — no OAuth logic in OSS.
- The `MESHER_TIER` env var is the single source of truth for all feature gating decisions throughout the codebase.
- Spikes are the gate — no production code ships until all four spike tests pass.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, no existing code

### Established Patterns
- None yet — Phase 1 establishes the baseline patterns for all subsequent phases

### Integration Points
- Phase 1 creates the auth system and org/project structure that all future phases depend on
- Schema-per-org provisioning (ORG-06) established here is the isolation model for all future data

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-foundation-toolchain-spike*
*Context gathered: 2026-03-03*

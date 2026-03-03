# Phase 1: Foundation + Toolchain Spike - Research

**Researched:** 2026-03-03
**Domain:** Authentication, multi-tenancy, Docker deployment, proprietary toolchain validation (Mesh, Streem-2, LitUI)
**Confidence:** HIGH

## Summary

Phase 1 establishes the entire application foundation: user authentication (OSS email/password + SaaS Google OAuth), organization management with schema-per-org PostgreSQL isolation, project/API key management, Docker Compose deployment, and four toolchain spike tests proving Mesh/Streem-2/LitUI capabilities before production code ships.

The proprietary stack (Mesh v12+, Streem-2, LitUI) is well-equipped for this phase. Mesh provides built-in HTTP server with routing/middleware, PostgreSQL driver with connection pooling and transactions, actor model with supervisors, WebSocket server with rooms/broadcasting, and a Crypto stdlib (SHA-256/512, HMAC, UUID4, secure_compare). Streem-2 provides reactive signals, JSX components, and `fromWebSocket()` with built-in exponential backoff reconnection. LitUI provides form components (input, button, dialog, tabs, toast) and chart components with streaming `pushData()` API using RAF coalescing.

**Primary recommendation:** Build auth with Mesh HTTP middleware for session validation, Valkey-backed sessions (not JWT -- server-side revocation needed for logout/password-reset), schema-per-org with `SET LOCAL search_path` inside `Pg.transaction()`, and all four spike tests as `.test.mpl` files in `spikes/`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **SaaS**: Google OAuth only -- single button, no email/password form, no tabs needed
- **Self-hosted (OSS)**: Email + password only -- no OAuth, no third-party dependencies
- Registration form fields (OSS): email + password only (no name field)
- Post-login landing: org setup wizard (first visit); subsequent logins land on org settings
- Email link with time-limited token (expires 1 hour) for password reset
- Runtime env var: `MESHER_TIER=oss` (default) or `MESHER_TIER=saas` for feature gating
- Docker Compose defaults to `oss`; SaaS deployment sets `saas`
- SaaS-only features from OSS instance: return HTTP 403 with "SaaS only" message
- SaaS Google OAuth: first sign-in auto-creates account and logs in (no separate registration step)
- Invite mechanism: email invite for both SaaS and OSS
- Invitee without account: clicking invite link -> registration form -> auto-join org after registration
- Invitee with existing account: clicking invite link -> auto-join immediately (no re-login needed)
- Invite validity: 7 days; owner can revoke pending invites from org settings
- Spikes in `spikes/` directory at repo root (separate from production code, deletable after Phase 1)
- Format: test files runnable with the project's test runner (`meshc test`)
- Four required spikes: (1) Mesh WebSocket actor supervision, (2) PG transaction pooling with SET LOCAL, (3) Streem-2 fromWebSocket() reconnection, (4) LitUI chart live-update performance

### Claude's Discretion
- Session storage mechanism (JWT vs Valkey-backed sessions)
- Schema migration strategy for per-org schemas
- Docker Compose service names, port assignments, volume naming
- Exact invite email copy and templates
- Error state UX on auth forms (where and how errors display)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTH-01 | Self-hosted user can register with email and password | Mesh HTTP server + `Pg.execute` for user INSERT + `Crypto.sha256`/HMAC for password hashing + LitUI `lui-input` type="email"/"password" + `lui-button` |
| AUTH-02 | User can log in and maintain session across browser refreshes | Valkey-backed session with secure cookie; Mesh middleware checks session on every request; `Env.get` for config |
| AUTH-03 | User can log out from any page | Session deletion from Valkey; Mesh HTTP endpoint clears cookie |
| AUTH-04 | Self-hosted user can reset password via email link | `Crypto.uuid4()` for token generation, `DateTime.add` for 1-hour expiry, SMTP via Mesh `Http.build(:post)` to email service or direct SMTP actor |
| AUTH-05 | SaaS user can sign in with Google OAuth | Google OAuth 2.0 authorization code flow; `MESHER_TIER=saas` env var gating; `Http.build` for token exchange |
| ORG-01 | User can create an organization and become owner | `Pg.execute` INSERT into orgs table + `CREATE SCHEMA` for org isolation |
| ORG-02 | Organization owner can invite members by email | Invite record in DB + SMTP email with time-limited accept link using `Crypto.uuid4()` |
| ORG-03 | Invited user can accept invitation and join | Token validation endpoint + membership INSERT; handles both existing and new users |
| ORG-04 | User can create a project scoped to organization | `Pg.execute` INSERT into projects within org schema; `SET LOCAL search_path` for tenant isolation |
| ORG-05 | User can generate and revoke API keys / DSNs per project | `Crypto.uuid4()` for key generation; `Crypto.sha256` for key hashing in storage; revoke = soft delete |
| ORG-06 | Each organization provisioned with own PostgreSQL schema at signup | `CREATE SCHEMA org_{uuid}` + run migrations on new schema; `SET LOCAL search_path` in every transaction |
| DEPLOY-01 | Full stack runs with `docker compose up` (app, TimescaleDB, Valkey) | `timescale/timescaledb:latest-pg17` + `valkey/valkey:9-alpine` + custom Mesh app image |
| DEPLOY-02 | All config driven by environment variables | Mesh `Env.get`/`Env.get_int` for all runtime config; Docker Compose `.env` file |
| DEPLOY-03 | Docker Compose includes health checks and dependency ordering | `pg_isready` for TimescaleDB; `valkey-cli ping` for Valkey; `depends_on` with condition `service_healthy` |
</phase_requirements>

## Standard Stack

### Core

| Library/Tool | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| Mesh | v12+ (latest) | Backend language: HTTP server, actors, PG driver, crypto | Proprietary -- project constraint; built-in HTTP/WS/PG/Crypto eliminates external deps |
| Streem-2 | latest | Frontend framework: reactive signals, JSX, WebSocket streams | Proprietary -- project constraint; `fromWebSocket()` has built-in reconnection |
| LitUI (lit-components) | latest | Component library: forms, charts, UI primitives | Proprietary -- project constraint; web components work with Streem-2 via `prop:` binding |
| PostgreSQL + TimescaleDB | PG 17 + TimescaleDB latest | Primary database with time-series extension | Project decision -- Mesh has native PG driver; TimescaleDB adds time-series as PG extension |
| Valkey | 9.x | Session store, cache | Redis-compatible drop-in; open-source fork; used for server-side session storage |

### Supporting

| Library/Tool | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| Docker + Docker Compose | latest | Local development and self-hosted deployment | DEPLOY-01/02/03 -- single-command stack startup |
| Vite | latest | Frontend build tool | Streem-2 JSX compilation, dev server, HMR |
| ECharts | 5.x (bundled in LitUI) | Chart rendering engine | Already bundled inside LitUI chart components; no separate install needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|-----------|-----------|----------|
| Valkey sessions | JWT tokens | JWT cannot be server-side revoked without a blocklist (which is just a session store). Valkey gives immediate logout/password-reset invalidation. Use Valkey. |
| Schema-per-org | Row-Level Security | RLS is simpler for migrations at scale but weaker isolation. Project decision locked schema-per-org for strong data boundaries. |
| SMTP direct | Transactional email service API | Direct SMTP is simpler for OSS self-hosted. For SaaS, could add SendGrid/Postmark later. Start with SMTP. |

## Architecture Patterns

### Recommended Project Structure

```
mesher/
├── src/
│   ├── main.mpl              # Entry point: pool, services, HTTP/WS setup
│   ├── auth/
│   │   ├── handlers.mpl       # Login, register, logout, reset HTTP handlers
│   │   ├── session.mpl        # Valkey session create/validate/destroy
│   │   ├── oauth.mpl          # Google OAuth flow (SaaS only)
│   │   └── middleware.mpl     # Auth middleware for HTTP router
│   ├── org/
│   │   ├── handlers.mpl       # Org CRUD, invite, accept handlers
│   │   ├── schema.mpl         # Schema provisioning (CREATE SCHEMA, migrations)
│   │   └── service.mpl        # OrgService (stateful service actor)
│   ├── project/
│   │   ├── handlers.mpl       # Project CRUD, API key handlers
│   │   └── service.mpl        # ProjectService
│   ├── user/
│   │   ├── handlers.mpl       # User profile handlers
│   │   └── service.mpl        # UserService
│   ├── mail/
│   │   └── sender.mpl         # SMTP email sending actor
│   ├── db/
│   │   ├── migrations/        # SQL migration files
│   │   └── tenant.mpl         # Tenant-scoped query helpers (SET LOCAL)
│   └── config.mpl             # Env var loading, tier detection
├── frontend/
│   ├── src/
│   │   ├── app.tsx            # Root Streem-2 component
│   │   ├── pages/
│   │   │   ├── login.tsx      # OSS login form / SaaS Google button
│   │   │   ├── register.tsx   # OSS registration form
│   │   │   ├── reset.tsx      # Password reset flow
│   │   │   ├── org-setup.tsx  # Org setup wizard (first visit)
│   │   │   └── org-settings.tsx # Org settings (invites, projects, keys)
│   │   └── components/
│   │       └── ...            # Shared UI components
│   ├── vite.config.ts
│   └── tsconfig.json
├── spikes/                    # Toolchain spike tests (deletable after Phase 1)
│   ├── ws_actor_supervision.test.mpl
│   ├── pg_set_local.test.mpl
│   ├── ws_reconnect.test.mpl  # (may need a JS test runner for browser-side)
│   └── chart_live_update.test.mpl  # (may need a browser-based test)
├── docker-compose.yml
├── Dockerfile
├── .env.example
└── mesh.toml
```

### Pattern 1: Tier-Gated Feature Access

**What:** Use `MESHER_TIER` env var to gate SaaS-only features at the HTTP middleware level.
**When to use:** Any endpoint or UI feature that differs between OSS and SaaS.

```mesh
# Source: CONTEXT.md decisions + Mesh Env.get API
fn tier_gate(request :: Request, next) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let path = Request.path(request)
  let is_saas_only = String.starts_with(path, "/api/v1/ai/")
  if is_saas_only do
    if tier == "saas" do
      next(request)
    else
      HTTP.response(403, json { error: "SaaS only" })
    end
  else
    next(request)
  end
end
```

### Pattern 2: Schema-Per-Org with SET LOCAL

**What:** Every database operation within an org context uses `SET LOCAL search_path` inside a transaction.
**When to use:** All org-scoped queries (projects, API keys, events, metrics).

```mesh
# Source: Mesh Pg.transaction API + PostgreSQL SET LOCAL docs
fn with_org_schema(pool, org_id :: String, query_fn) do
  let conn = Pool.checkout(pool)?
  let _ = Pg.begin(conn)?
  let _ = Pg.execute(conn, "SET LOCAL search_path TO org_#{org_id}, public, extensions", [])?
  let result = query_fn(conn)
  case result do
    Ok(val) ->
      let _ = Pg.commit(conn)?
      Pool.checkin(pool, conn)
      Ok(val)
    Err(e) ->
      let _ = Pg.rollback(conn)?
      Pool.checkin(pool, conn)
      Err(e)
  end
end
```

### Pattern 3: Valkey-Backed Sessions

**What:** Server-side sessions stored in Valkey with secure HTTP-only cookies.
**When to use:** All authenticated requests.

**Recommended approach (Claude's Discretion):** Use Valkey for session storage. Each session is a Valkey key (`session:{uuid}`) with a JSON value containing `user_id`, `org_id`, `created_at`, and `expires_at`. The session UUID is sent as a secure, HTTP-only, SameSite=Strict cookie. Session TTL in Valkey provides automatic expiry.

**Why not JWT:** The user decisions require logout from any page (AUTH-03) and password reset invalidation (AUTH-04). JWT cannot be revoked server-side without maintaining a blocklist, which is functionally equivalent to a session store. Valkey sessions give immediate revocation with simpler implementation.

**Note on Valkey client:** Mesh does not have a built-in Valkey/Redis client in the stdlib documented in GitNexus. This will need to be implemented either as a raw TCP socket client speaking the RESP protocol, or by using Mesh's `Http.build` against a Valkey HTTP proxy. **This is an open question that needs resolution early in implementation.** Alternative: use PostgreSQL-only sessions (a `sessions` table with periodic cleanup) to avoid the Valkey dependency for auth. The Valkey service would then only be needed in later phases for caching/rate-limiting.

### Pattern 4: Auth Middleware

**What:** HTTP middleware that validates session cookie on every request, injects user context.
**When to use:** All authenticated API routes.

```mesh
# Source: Mesh HTTP middleware pattern from skills/http
fn auth_middleware(request :: Request, next) -> Response do
  let cookie = Request.header(request, "cookie")
  case cookie do
    Some(cookie_str) ->
      # Extract session_id from cookie, validate against session store
      let session = validate_session(cookie_str)
      case session do
        Some(user) -> next(request)  # Pass through with user context
        None -> HTTP.response(401, json { error: "unauthorized" })
      end
    None -> HTTP.response(401, json { error: "unauthorized" })
  end
end
```

### Pattern 5: Streem-2 + LitUI Integration

**What:** Use Streem-2 signals with LitUI web components via `prop:` binding for reactive data flow.
**When to use:** All frontend UI that uses LitUI components.

```typescript
// Source: Streem-2 skills/lit SKILL.md + LitUI skills/framework-usage
import { signal, effect } from 'streem'
import '@lit-ui/input'
import '@lit-ui/button'

function LoginForm() {
  const email = signal('')
  const password = signal('')
  const error = signal<string | undefined>(undefined)

  async function handleSubmit() {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.value, password: password.value }),
    })
    if (!res.ok) error.set('Invalid credentials')
    else window.location.href = '/org'
  }

  return (
    <form onSubmit={(e) => { e.preventDefault(); handleSubmit() }}>
      <lui-input
        type="email"
        label="Email"
        placeholder="you@example.com"
        required
        on:input={(e: Event) => email.set((e.target as any).value)}
      />
      <lui-input
        type="password"
        label="Password"
        required
        on:input={(e: Event) => password.set((e.target as any).value)}
      />
      <Show when={() => error.value !== undefined}>
        {() => <div class="text-red-500">{() => error.value}</div>}
      </Show>
      <lui-button variant="primary" type="submit">Sign In</lui-button>
    </form>
  )
}
```

### Anti-Patterns to Avoid

- **Storing passwords as plain SHA-256:** SHA-256 is fast and vulnerable to rainbow tables. Use HMAC-SHA256 with a per-user salt (or ideally bcrypt if available). Mesh provides `Crypto.hmac_sha256(key, msg)` -- use a server secret + per-user salt as the key.
- **Using `SET` instead of `SET LOCAL`:** `SET search_path` is session-scoped and persists after transaction end. With connection pooling, the next request on the same connection inherits the wrong tenant's schema. Always use `SET LOCAL` inside a transaction.
- **Setting LitUI object props as HTML attributes:** Object/array properties like `data` and `columns` MUST be set via JavaScript property assignment, not HTML attributes. Use `prop:data` in Streem-2 JSX or `ref.current.data = ...` pattern.
- **Calling `chart.option = ...` after `pushData()` has started:** This wipes streamed data. Once streaming starts, only use `pushData()` for data updates.
- **Importing ECharts at module top level in LitUI:** ECharts must be dynamically imported inside `firstUpdated()` for SSR safety. This is handled by BaseChartElement internally -- never import echarts at top level in consuming code.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Password hashing | Custom hash scheme | `Crypto.hmac_sha256(server_secret <> salt, password)` | HMAC with per-user salt provides protection against rainbow tables; Mesh Crypto is backed by Rust sha2/hmac crates |
| Session tokens | Sequential IDs or timestamps | `Crypto.uuid4()` | Cryptographically random; RFC 4122 v4; 122 bits of entropy |
| WebSocket reconnection | Custom retry loop in frontend | `fromWebSocket(url, { reconnect: { maxRetries, initialDelay, maxDelay } })` | Streem-2 handles exponential backoff with jitter, cleanup on scope disposal, status signals |
| Chart streaming & RAF batching | Manual requestAnimationFrame loop | `chart.pushData(point)` | LitUI BaseChartElement handles RAF coalescing, circular buffer, Float32Array conversion |
| JSON responses | Manual string concatenation | `json { key: value }` literals | Type-safe, auto-coercing, no escaping bugs; `HTTP.response(200, json { ... })` |
| Actor crash recovery | try/catch wrappers | `supervisor` blocks with restart strategies | Mesh supervisors handle restart budgets, strategies (one_for_one, one_for_all), and tree propagation |
| Connection pooling | Manual connection management | `Pool.open(url, min, max, timeout_ms)` | Auto checkout/checkin, health checks, transaction rollback on dirty return, timeout handling |
| Form validation display | Custom error state management | LitUI `lui-input` built-in validation | Shows errors after blur (touched state), uses native `validationMessage`, supports required/minlength/pattern |

**Key insight:** The proprietary stack has an unusually complete set of built-in capabilities (HTTP, WS, PG, Crypto, test runner, actor model). The main gaps are: (1) no built-in Valkey/Redis client in Mesh, and (2) no built-in bcrypt (only SHA-256/512 and HMAC).

## Common Pitfalls

### Pitfall 1: Schema-Per-Org Migration Complexity

**What goes wrong:** As org count grows, migrations must run N times (once per schema). 200 orgs means 45+ minute deploys.
**Why it happens:** Each `ALTER TABLE` or `CREATE INDEX` must execute against every org schema independently.
**How to avoid:** Design a migration runner that iterates over all org schemas. Keep schema DDL minimal in early phases. Batch migrations in a background job, not in the deploy pipeline. Consider a `schema_version` column in the public `organizations` table to track per-org migration state.
**Warning signs:** Deploy times growing linearly with org count; migration failures leaving some schemas in inconsistent state.

### Pitfall 2: SET LOCAL Forgotten or Misplaced

**What goes wrong:** Queries execute against the wrong tenant's schema, causing data leakage or errors.
**Why it happens:** Developer forgets to wrap org-scoped queries in a transaction with `SET LOCAL`, or uses `SET` (session-scoped) instead.
**How to avoid:** Create a `with_org_schema(pool, org_id, fn)` helper that wraps all org-scoped DB operations. Never execute org-scoped SQL outside this wrapper. The pool's auto-rollback on checkin (verified in pool.rs source) provides a safety net.
**Warning signs:** Tests passing in isolation but failing under concurrent load; data from one org appearing in another org's queries.

### Pitfall 3: Password Hashing Without Salt

**What goes wrong:** Identical passwords produce identical hashes, enabling rainbow table attacks.
**Why it happens:** Using `Crypto.sha256(password)` directly without a per-user salt.
**How to avoid:** Generate a random salt per user with `Crypto.uuid4()`. Store the salt alongside the hash. Hash as `Crypto.hmac_sha256(server_secret <> salt, password)`. Verify by re-computing and using `Crypto.secure_compare()` (constant-time).
**Warning signs:** Multiple users with the same password having identical stored hashes.

### Pitfall 4: Google OAuth State Parameter Missing

**What goes wrong:** CSRF attacks redirect users to attacker-controlled OAuth callbacks.
**Why it happens:** Skipping the `state` parameter in the OAuth authorization URL.
**How to avoid:** Generate a random `state` value with `Crypto.uuid4()`, store it in the session/cookie before redirect, and verify it matches on callback. Google's official docs explicitly require this.
**Warning signs:** OAuth flow works without state validation in testing but is vulnerable in production.

### Pitfall 5: WebSocket Actor Crash Leaking Connections

**What goes wrong:** A crashed WebSocket handler actor leaves the TCP connection open, consuming resources.
**Why it happens:** The supervisor restarts the actor but the old WebSocket connection state is lost.
**How to avoid:** Mesh's WS runtime already isolates each connection as an actor -- if the handler crashes, only that connection is affected and the server continues. The spike test should verify this behavior explicitly. Room membership is automatically cleaned up on disconnect.
**Warning signs:** Connection count growing over time despite clients disconnecting; memory leaks in long-running WS servers.

### Pitfall 6: PostgreSQL Extensions Not in search_path

**What goes wrong:** TimescaleDB functions (`create_hypertable`, `time_bucket`) fail with "function does not exist" after switching search_path.
**Why it happens:** Extensions are installed in the `public` schema, which gets dropped from `search_path` when switching to an org schema.
**How to avoid:** Always include `public` in the search_path: `SET LOCAL search_path TO org_{id}, public`. Alternatively, create an `extensions` schema for TimescaleDB and include it.
**Warning signs:** Queries work in `psql` but fail through the application; TimescaleDB functions unavailable after schema switch.

### Pitfall 7: Invite Token Reuse

**What goes wrong:** An expired or used invite token is accepted, allowing unauthorized org access.
**Why it happens:** Token validation only checks existence, not expiry or used status.
**How to avoid:** Store `expires_at` (7 days from creation) and `accepted_at` (null until used). Validate both on accept. Delete or mark as consumed after acceptance. Use `DateTime.is_before(DateTime.utc_now(), expires_at)` for expiry check.
**Warning signs:** Users joining orgs from old invite links; revoked invites still being accepted.

## Code Examples

### Mesh HTTP Server with Auth Middleware

```mesh
# Source: Mesh skills/http + skills/strings
fn main() do
  let pool = Pool.open(Env.get("DATABASE_URL", "postgres://mesh:mesh@localhost:5432/mesher"), 2, 10, 5000)?

  let router = HTTP.router()
    |> HTTP.use(cors_middleware)
    |> HTTP.use(tier_gate)
    |> HTTP.on_post("/api/auth/register", register_handler)
    |> HTTP.on_post("/api/auth/login", login_handler)
    |> HTTP.on_post("/api/auth/logout", logout_handler)
    |> HTTP.on_post("/api/auth/reset-password", reset_password_handler)
    |> HTTP.on_post("/api/auth/reset-password/confirm", confirm_reset_handler)
    |> HTTP.on_get("/api/auth/oauth/google", google_oauth_start)
    |> HTTP.on_get("/api/auth/oauth/google/callback", google_oauth_callback)
    |> HTTP.use(auth_middleware)  # Everything below requires auth
    |> HTTP.on_post("/api/orgs", create_org_handler)
    |> HTTP.on_post("/api/orgs/:org_id/invites", create_invite_handler)
    |> HTTP.on_post("/api/invites/:token/accept", accept_invite_handler)
    |> HTTP.on_post("/api/orgs/:org_id/projects", create_project_handler)
    |> HTTP.on_post("/api/projects/:project_id/api-keys", create_api_key_handler)
    |> HTTP.on_post("/api/api-keys/:key_id/revoke", revoke_api_key_handler)

  let port = Env.get_int("PORT", 8080)
  HTTP.serve(router, port)
end
```

### Schema Provisioning on Org Creation

```mesh
# Source: Mesh skills/database + PostgreSQL CREATE SCHEMA
fn provision_org_schema(pool, org_id :: String) -> Int!String do
  let conn = Pool.checkout(pool)?

  # Create the org schema
  let _ = Pg.execute(conn, "CREATE SCHEMA IF NOT EXISTS org_#{org_id}", [])?

  # Run base migrations in the new schema
  let _ = Pg.begin(conn)?
  let _ = Pg.execute(conn, "SET LOCAL search_path TO org_#{org_id}, public", [])?
  let _ = Pg.execute(conn, """
    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
    """, [])?
  let _ = Pg.execute(conn, """
    CREATE TABLE IF NOT EXISTS api_keys (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL REFERENCES projects(id),
      key_hash TEXT NOT NULL,
      prefix TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      revoked_at TIMESTAMPTZ
    )
    """, [])?
  let _ = Pg.commit(conn)?

  Pool.checkin(pool, conn)
  Ok(0)
end
```

### WebSocket Server with Actor Isolation

```mesh
# Source: Mesh skills/http WebSocket section + existing mesher/main.mpl pattern
fn on_connect(conn) do
  Ws.send(conn, json { type: "connected" })
end

fn on_message(conn, msg) do
  Ws.send(conn, json { type: "echo", data: msg })
end

fn on_close(conn) do
  println("[WS] Connection closed")
end

fn main() do
  let ws_port = Env.get_int("WS_PORT", 8081)
  Ws.serve(on_connect, on_message, on_close, ws_port)
end
```

### Streem-2 fromWebSocket with Reconnection

```typescript
// Source: Streem-2 skills/streams SKILL.md + from-websocket.ts source
import { createRoot } from 'streem'
import { fromWebSocket } from 'streem/streams'
import { effect } from 'streem/core'

createRoot(() => {
  const [data, status, error] = fromWebSocket<{ type: string; payload: unknown }>(
    'ws://localhost:8081',
    {
      transform: (raw) => raw as { type: string; payload: unknown },
      reconnect: {
        maxRetries: 10,
        initialDelay: 1000,  // 1 second
        maxDelay: 30000,     // 30 seconds
      },
    },
  )

  effect(() => {
    console.log('Status:', status.value)  // connecting -> connected -> reconnecting -> connected
    if (status.value === 'connected' && data.value) {
      console.log('Message:', data.value)
    }
  })
})
```

### LitUI Chart Live Streaming

```typescript
// Source: LitUI skills/charts + skills/line-chart SKILL.md
import '@lit-ui/charts/line-chart'

const chart = document.querySelector('lui-line-chart')!
// Initialize with empty series
;(chart as any).data = [{ name: 'Live Metric', data: [] }]

// Stream data at high frequency -- pushData RAF-coalesces automatically
setInterval(() => {
  ;(chart as any).pushData(Math.random() * 100)
}, 16)  // ~60fps input rate, batched to actual 60fps renders
```

### Docker Compose Configuration

```yaml
# Source: TimescaleDB Docker Hub + Valkey Docker Hub + project decisions
services:
  app:
    build: .
    ports:
      - "${HTTP_PORT:-8080}:8080"
      - "${WS_PORT:-8081}:8081"
    environment:
      DATABASE_URL: "postgres://mesh:mesh@timescaledb:5432/mesher"
      VALKEY_URL: "valkey://valkey:6379"
      MESHER_TIER: "${MESHER_TIER:-oss}"
      SMTP_HOST: "${SMTP_HOST:-}"
      SMTP_PORT: "${SMTP_PORT:-587}"
      SMTP_USER: "${SMTP_USER:-}"
      SMTP_PASS: "${SMTP_PASS:-}"
      GOOGLE_CLIENT_ID: "${GOOGLE_CLIENT_ID:-}"
      GOOGLE_CLIENT_SECRET: "${GOOGLE_CLIENT_SECRET:-}"
    depends_on:
      timescaledb:
        condition: service_healthy
      valkey:
        condition: service_healthy
    restart: unless-stopped

  timescaledb:
    image: timescale/timescaledb:latest-pg17
    environment:
      POSTGRES_DB: mesher
      POSTGRES_USER: mesh
      POSTGRES_PASSWORD: mesh
      TIMESCALEDB_TELEMETRY: "off"
    ports:
      - "5432:5432"
    volumes:
      - timescaledb_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mesh -d mesher"]
      interval: 10s
      timeout: 5s
      retries: 5

  valkey:
    image: valkey/valkey:9-alpine
    ports:
      - "6379:6379"
    volumes:
      - valkey_data:/data
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  timescaledb_data:
  valkey_data:
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|-------------|------------------|--------------|--------|
| Redis sessions | Valkey sessions | 2024 (Redis license change) | Valkey is the community-maintained Redis fork; API-compatible; use `valkey/valkey` Docker image |
| JWT for web auth | Server-side sessions | Ongoing best practice | JWTs cannot be revoked; server-side sessions are simpler and more secure for web apps with logout requirements |
| Google Sign-In JS library | OAuth 2.0 Authorization Code flow | 2023 (GSI library deprecated) | Use server-side authorization code flow with PKCE; Google still requires client_secret for web apps |
| PgBouncer for pooling | Mesh built-in Pool module | N/A (Mesh-specific) | Mesh has its own connection pool with health checks and auto-rollback; no external pooler needed |
| Manual chart rendering | LitUI ECharts web components | N/A (project-specific) | `pushData()` with RAF coalescing handles high-frequency streaming automatically |

**Deprecated/outdated:**
- Google Sign-In JavaScript library: Use OAuth 2.0 server-side flow instead
- Redis for new projects: Use Valkey (open-source Redis fork) instead
- OOB (out-of-band) redirect for OAuth: Deprecated by Google; use proper redirect URI

## Open Questions

1. **Valkey Client in Mesh**
   - What we know: Mesh has built-in HTTP client, PG client, and SQLite client, but no Valkey/Redis client in the documented stdlib.
   - What's unclear: Whether Mesh has an undocumented Valkey client, or if one needs to be built using raw TCP sockets or the RESP protocol.
   - Recommendation: **Fall back to PostgreSQL-based sessions** if no Valkey client is available. Store sessions in a `public.sessions` table with a background cleanup job for expired sessions. This eliminates the Valkey dependency for Phase 1 auth while keeping Valkey in Docker Compose for future phases (caching, rate limiting). Alternatively, check if Mesh has a generic TCP socket API that could implement a minimal RESP client.

2. **Bcrypt Availability in Mesh**
   - What we know: Mesh Crypto provides SHA-256, SHA-512, HMAC-SHA256, HMAC-SHA512, secure_compare, and UUID4. No bcrypt/scrypt/argon2.
   - What's unclear: Whether the Mesh Crypto module has additional functions not documented, or if a package exists in the Mesh registry.
   - Recommendation: Use HMAC-SHA256 with a server-side secret key + per-user random salt. This is not as resistant to brute-force as bcrypt (no work factor), but is standard for web applications without bcrypt. Store as `hmac_sha256(SERVER_SECRET + user_salt, password)`. **Flag this as a known limitation** -- upgrade to bcrypt/argon2 if/when Mesh adds support or a package becomes available.

3. **Mesh Migration Tool**
   - What we know: Mesh has `meshc migrate` which uses a tracking table for migrations. The runtime has `compiler/meshc/src/migrate.rs` with `CREATE_TRACKING_TABLE` and `MigrationInfo`.
   - What's unclear: Whether `meshc migrate` supports running migrations against arbitrary schemas (not just the default), which is needed for per-org schema provisioning.
   - Recommendation: For per-org schema migrations, write a Mesh function that iterates over all org schemas and executes migration SQL with `SET LOCAL search_path` per schema. Use `meshc migrate` for the public schema (auth tables, org registry), and custom code for per-org schemas.

4. **SMTP in Mesh**
   - What we know: Mesh has `Http.build` for HTTP requests but no documented SMTP client.
   - What's unclear: Whether to use an HTTP-based email API (SendGrid, Mailgun) or implement SMTP directly.
   - Recommendation: For OSS self-hosted, provide env vars for SMTP config. Implement email sending as an HTTP POST to an SMTP relay service (most SMTP services have HTTP APIs). For the initial spike, email sending can be mocked. For production, if raw SMTP is needed, check Mesh TCP socket capabilities or use an SMTP-to-HTTP bridge container.

5. **Streem-2 and LitUI Spike Tests**
   - What we know: The WS reconnection and chart live-update spikes are frontend (browser) tests. Mesh's `meshc test` runs `.test.mpl` files -- these are backend tests.
   - What's unclear: How to run browser-based spike tests for Streem-2 fromWebSocket() reconnection and LitUI chart performance.
   - Recommendation: The Streem-2 reconnection spike can be tested in Node.js with a mock WebSocket server (the fromWebSocket source uses standard WebSocket API). The LitUI chart performance spike likely needs a browser environment -- use a simple HTML page with a script that measures frame timing via `requestAnimationFrame` and `performance.now()`. Both can be validated manually or with a lightweight browser test runner.

## Sources

### Primary (HIGH confidence)
- GitNexus `mesh` repo -- Mesh skills (actors, supervisors, http, database, strings), runtime source (pool.rs, crypto.rs, actor/supervisor.rs), website docs (testing, stdlib, databases, web)
- GitNexus `streem-2` repo -- Streem-2 skills (signals, components, streams, lit), source (from-websocket.ts, types.ts, reactive.ts)
- GitNexus `lit-components` repo -- LitUI skills (charts, line-chart, input, button, framework-usage), source (base-chart-element.ts, line-chart.ts, area-chart demo)
- Existing Mesher code in `mesh` repo -- `mesher/main.mpl`, `mesher/ingestion/ws_handler.mpl` (real-world Mesh application patterns)

### Secondary (MEDIUM confidence)
- [TimescaleDB Docker Hub](https://hub.docker.com/r/timescale/timescaledb) -- Image tags, health check patterns, tuning env vars
- [Valkey Docker Hub](https://hub.docker.com/r/valkey/valkey/) -- Image tags (9.x), configuration, health check
- [Google OAuth 2.0 Web Server Flow](https://developers.google.com/identity/protocols/oauth2/web-server) -- Authorization code flow, PKCE, state parameter
- [Google OAuth Best Practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices) -- Credential security, incremental scopes, token handling
- [Arkency: Multitenancy with Postgres Schemas](https://blog.arkency.com/multitenancy-with-postgres-schemas-key-concepts-explained/) -- SET LOCAL search_path pattern, migration challenges
- [Crunchy Data: Designing Postgres for Multi-tenancy](https://www.crunchydata.com/blog/designing-your-postgres-database-for-multi-tenancy) -- Schema-per-tenant vs RLS tradeoffs
- [Schema-Based Multi-Tenancy Deep Dive](https://blog.thnkandgrow.com/a-deep-dive-into-schema-based-multi-tenancy-scaling-maintenance-and-best-practices/) -- Migration strategies, scaling limits, extension schema pattern

### Tertiary (LOW confidence)
- Password hashing without bcrypt: HMAC-SHA256 with per-user salt is a reasonable fallback but not industry-standard for password storage. Flag for upgrade.
- Mesh SMTP capabilities: No direct evidence of SMTP support in Mesh stdlib. Needs validation during implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All three proprietary tools verified via GitNexus source code and skill docs; Docker images verified via official registries
- Architecture: HIGH -- Patterns derived from actual Mesh code (existing mesher/main.mpl), official Mesh docs, and verified Streem-2/LitUI APIs
- Pitfalls: HIGH -- Schema-per-org pitfalls verified via multiple sources; WebSocket actor isolation verified in Mesh runtime source; SET LOCAL requirement verified in PostgreSQL docs and pooling best practices
- Toolchain spikes: MEDIUM -- Mesh and Streem-2 backend spikes straightforward; browser-based spikes (chart performance, WS reconnect) may need non-standard test setup

**Research date:** 2026-03-03
**Valid until:** 2026-04-03 (30 days -- proprietary stack is in beta but APIs are stable based on GitNexus evidence)

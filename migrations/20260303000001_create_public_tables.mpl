# Migration: Create public schema tables
# Creates all shared tables: users, organizations, org_memberships,
# sessions, invites, and password_reset_tokens.

fn up(pool) -> Int!String do
  # Users table (public schema -- shared across all orgs)
  let _ = Pool.execute(pool, "CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    password_salt TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )", [])?

  # Organizations table (public schema -- org registry)
  let _ = Pool.execute(pool, "CREATE TABLE IF NOT EXISTS organizations (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL REFERENCES users(id),
    schema_name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )", [])?

  # Organization memberships (public schema)
  let _ = Pool.execute(pool, "CREATE TABLE IF NOT EXISTS org_memberships (
    id TEXT PRIMARY KEY,
    org_id TEXT NOT NULL REFERENCES organizations(id),
    user_id TEXT NOT NULL REFERENCES users(id),
    role TEXT NOT NULL DEFAULT 'member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, user_id)
  )", [])?

  # Sessions table (public schema -- PG-backed sessions)
  # Using PostgreSQL sessions with periodic cleanup rather than Valkey,
  # since Mesh may not have a built-in Valkey client (see research open question #1).
  let _ = Pool.execute(pool, "CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )", [])?

  # Invites table (public schema)
  let _ = Pool.execute(pool, "CREATE TABLE IF NOT EXISTS invites (
    id TEXT PRIMARY KEY,
    org_id TEXT NOT NULL REFERENCES organizations(id),
    email TEXT NOT NULL,
    token TEXT NOT NULL UNIQUE,
    invited_by TEXT NOT NULL REFERENCES users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )", [])?

  # Password reset tokens (public schema)
  let _ = Pool.execute(pool, "CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )", [])?

  # Indexes for query performance
  let _ = Pool.execute(pool, "CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)", [])?
  let _ = Pool.execute(pool, "CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at)", [])?
  let _ = Pool.execute(pool, "CREATE INDEX IF NOT EXISTS idx_invites_token ON invites(token)", [])?
  let _ = Pool.execute(pool, "CREATE INDEX IF NOT EXISTS idx_invites_email ON invites(email)", [])?
  let _ = Pool.execute(pool, "CREATE INDEX IF NOT EXISTS idx_org_memberships_user ON org_memberships(user_id)", [])?

  Ok(0)
end

fn down(pool) -> Int!String do
  let _ = Pool.execute(pool, "DROP TABLE IF EXISTS password_reset_tokens", [])?
  let _ = Pool.execute(pool, "DROP TABLE IF EXISTS invites", [])?
  let _ = Pool.execute(pool, "DROP TABLE IF EXISTS sessions", [])?
  let _ = Pool.execute(pool, "DROP TABLE IF EXISTS org_memberships", [])?
  let _ = Pool.execute(pool, "DROP TABLE IF EXISTS organizations", [])?
  let _ = Pool.execute(pool, "DROP TABLE IF EXISTS users", [])?
  Ok(0)
end

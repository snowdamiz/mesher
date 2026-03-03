# Migration: Create all public schema tables using Mesh ORM.
# Single migration creates all tables with UUID PKs (gen_random_uuid()),
# proper FK references, and performance indexes.
# Tables are created in FK dependency order; dropped in reverse.

pub fn up(pool :: PoolHandle) -> Int!String do
  # Enable pgcrypto for gen_random_uuid() and bcrypt via crypt()/gen_salt()
  Pool.execute(pool, "CREATE EXTENSION IF NOT EXISTS pgcrypto", [])?

  # 1. organizations (no FKs -- root table)
  Migration.create_table(pool, "organizations", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "name:TEXT:NOT NULL",
    "slug:TEXT:NOT NULL UNIQUE",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # 2. users (no FKs -- root table)
  Migration.create_table(pool, "users", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "email:TEXT:NOT NULL UNIQUE",
    "password_hash:TEXT:NOT NULL",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # 3. org_memberships (FKs to users + organizations, composite UNIQUE)
  Pool.execute(pool, "CREATE TABLE org_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, org_id)
  )", [])?

  # 4. sessions (token TEXT PK, FK to users)
  Migration.create_table(pool, "sessions", [
    "token:TEXT:PRIMARY KEY",
    "user_id:UUID:NOT NULL REFERENCES users(id) ON DELETE CASCADE",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()",
    "expires_at:TIMESTAMPTZ:NOT NULL DEFAULT now() + interval '7 days'"
  ])?

  # 5. invites (FKs to organizations + users)
  Migration.create_table(pool, "invites", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "org_id:UUID:NOT NULL REFERENCES organizations(id) ON DELETE CASCADE",
    "email:TEXT:NOT NULL",
    "token:TEXT:NOT NULL UNIQUE",
    "invited_by:UUID:NOT NULL REFERENCES users(id)",
    "expires_at:TIMESTAMPTZ:NOT NULL",
    "accepted_at:TIMESTAMPTZ",
    "revoked_at:TIMESTAMPTZ",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # 6. password_reset_tokens (FK to users)
  Migration.create_table(pool, "password_reset_tokens", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "user_id:UUID:NOT NULL REFERENCES users(id) ON DELETE CASCADE",
    "token_hash:TEXT:NOT NULL UNIQUE",
    "expires_at:TIMESTAMPTZ:NOT NULL",
    "used_at:TIMESTAMPTZ",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # 7. projects (FK to organizations)
  Migration.create_table(pool, "projects", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "org_id:UUID:NOT NULL REFERENCES organizations(id) ON DELETE CASCADE",
    "name:TEXT:NOT NULL",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # 8. api_keys (FK to projects)
  Migration.create_table(pool, "api_keys", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "project_id:UUID:NOT NULL REFERENCES projects(id) ON DELETE CASCADE",
    "key_hash:TEXT:NOT NULL",
    "key_prefix:TEXT:NOT NULL",
    "label:TEXT:NOT NULL DEFAULT 'default'",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()",
    "revoked_at:TIMESTAMPTZ"
  ])?

  # Performance indexes
  Pool.execute(pool, "CREATE INDEX idx_org_memberships_user ON org_memberships(user_id)", [])?
  Pool.execute(pool, "CREATE INDEX idx_org_memberships_org ON org_memberships(org_id)", [])?
  Pool.execute(pool, "CREATE INDEX idx_sessions_user ON sessions(user_id)", [])?
  Pool.execute(pool, "CREATE INDEX idx_sessions_expires ON sessions(expires_at)", [])?
  Pool.execute(pool, "CREATE INDEX idx_invites_token ON invites(token)", [])?
  Pool.execute(pool, "CREATE INDEX idx_invites_email ON invites(email)", [])?
  Pool.execute(pool, "CREATE INDEX idx_projects_org ON projects(org_id)", [])?
  Pool.execute(pool, "CREATE INDEX idx_api_keys_project ON api_keys(project_id)", [])?
  Pool.execute(pool, "CREATE INDEX idx_api_keys_hash ON api_keys(key_hash) WHERE revoked_at IS NULL", [])?

  Ok(0)
end

pub fn down(pool :: PoolHandle) -> Int!String do
  # Drop in reverse FK dependency order
  Migration.drop_table(pool, "api_keys")?
  Migration.drop_table(pool, "projects")?
  Migration.drop_table(pool, "password_reset_tokens")?
  Migration.drop_table(pool, "invites")?
  Migration.drop_table(pool, "sessions")?
  Migration.drop_table(pool, "org_memberships")?
  Migration.drop_table(pool, "users")?
  Migration.drop_table(pool, "organizations")?
  Ok(0)
end

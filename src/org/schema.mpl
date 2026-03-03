# Organization schema provisioning (ORG-06)
#
# Provisions a dedicated PostgreSQL schema for each organization at creation time.
# Each org schema contains tenant-scoped tables (projects, api_keys).
# The search_path always includes 'public' so TimescaleDB extension functions
# remain accessible (Pitfall 6 in research).

# Sanitize an org ID for use as a PostgreSQL schema name.
# Replaces hyphens with underscores and prepends "org_".
pub fn schema_name_for_org(org_id :: String) -> String do
  "org_" <> String.replace(org_id, "-", "_")
end

# Provision a new org schema with tenant-scoped tables.
# Creates the schema and runs initial tenant table migrations.
#
# Creates:
#   - org_{sanitized_id} schema
#   - projects table (within org schema)
#   - api_keys table (within org schema, references projects)
pub fn provision_org_schema(pool, org_id :: String) -> Int!String do
  let schema_name = schema_name_for_org(org_id)
  let conn = Pool.checkout(pool)?

  # Create the org schema (DDL, not parameterizable)
  let _ = Pg.execute(conn, "CREATE SCHEMA IF NOT EXISTS #{schema_name}", [])?

  # Run tenant table migrations within the new schema
  let _ = Pg.begin(conn)?
  let _ = Pg.execute(conn, "SET LOCAL search_path TO #{schema_name}, public", [])?

  let _ = Pg.execute(conn, "CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())", [])?

  let _ = Pg.execute(conn, "CREATE TABLE IF NOT EXISTS api_keys (id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id), key_hash TEXT NOT NULL, key_prefix TEXT NOT NULL, label TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), revoked_at TIMESTAMPTZ)", [])?

  let _ = Pg.commit(conn)?

  Pool.checkin(pool, conn)
  Ok(0)
end

# Run tenant migrations on an existing org schema.
# Used when new tables or columns need to be added to all org schemas.
pub fn run_tenant_migrations(pool, org_id :: String) -> Int!String do
  let schema_name = schema_name_for_org(org_id)
  let conn = Pool.checkout(pool)?

  let _ = Pg.begin(conn)?
  let _ = Pg.execute(conn, "SET LOCAL search_path TO #{schema_name}, public", [])?

  # Future migrations go here (each should be idempotent with IF NOT EXISTS)

  let _ = Pg.commit(conn)?

  Pool.checkin(pool, conn)
  Ok(0)
end

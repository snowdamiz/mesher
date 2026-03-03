# Tenant-scoped query helper for schema-per-org isolation (ORG-06)
#
# Every database operation within an org context MUST use SET LOCAL search_path
# inside a transaction. This prevents search_path from leaking across pooled
# connections (see anti-pattern: using SET instead of SET LOCAL).
#
# The search_path always includes 'public' to ensure TimescaleDB extensions
# and shared tables remain accessible (see Pitfall 6 in research).

# Execute a query function within the context of an org's schema.
# Wraps the operation in a transaction with SET LOCAL search_path.
#
# Usage:
#   with_org_schema(pool, org_id, fn(conn) do
#     Pool.execute(conn, "SELECT * FROM projects", [])
#   end)
fn with_org_schema(pool, org_id :: String, query_fn) do
  let conn = Pool.checkout(pool)?
  let _ = Pg.begin(conn)?
  let _ = Pg.execute(conn, "SET LOCAL search_path TO org_#{org_id}, public", [])?

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

# Provision a new org schema with tenant-scoped tables.
# Called when a new organization is created.
#
# Creates:
#   - org_{org_id} schema
#   - projects table (within org schema)
#   - api_keys table (within org schema, references projects)
fn provision_org_schema(pool, org_id :: String) -> Int!String do
  let conn = Pool.checkout(pool)?

  # Create the org schema
  let _ = Pg.execute(conn, "CREATE SCHEMA IF NOT EXISTS org_#{org_id}", [])?

  # Run tenant table migrations within the new schema
  let _ = Pg.begin(conn)?
  let _ = Pg.execute(conn, "SET LOCAL search_path TO org_#{org_id}, public", [])?

  let _ = Pg.execute(conn, "CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )", [])?

  let _ = Pg.execute(conn, "CREATE TABLE IF NOT EXISTS api_keys (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id),
    key_hash TEXT NOT NULL,
    key_prefix TEXT NOT NULL,
    label TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
  )", [])?

  let _ = Pg.commit(conn)?

  Pool.checkin(pool, conn)
  Ok(0)
end

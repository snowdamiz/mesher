# Tenant-scoped query helper for schema-per-org isolation (ORG-06)
#
# Every database operation within an org context MUST use SET LOCAL search_path
# inside a transaction. This prevents search_path from leaking across pooled
# connections (see anti-pattern: using SET instead of SET LOCAL).
#
# The search_path always includes 'public' to ensure TimescaleDB extensions
# and shared tables remain accessible (see Pitfall 6 in research).

fn safe_checkin(pool, conn) do
  Pool.checkin(pool, conn)
end

fn commit_and_checkin(pool, conn, val) do
  let _ = Pg.commit(conn)
  safe_checkin(pool, conn)
  Ok(val)
end

fn rollback_and_checkin(pool, conn, err) do
  let _ = Pg.rollback(conn)
  safe_checkin(pool, conn)
  Err(err)
end

fn run_query_fn(pool, conn, query_fn) do
  let result = query_fn(conn)
  case result do
    Ok(val) -> commit_and_checkin(pool, conn, val)
    Err(e) -> rollback_and_checkin(pool, conn, e)
  end
end

fn set_search_path_and_run(pool, conn, org_id :: String, query_fn) do
  let set_result = Pg.execute(conn, "SET LOCAL search_path TO org_#{org_id}, public", [])
  case set_result do
    Ok(_) -> run_query_fn(pool, conn, query_fn)
    Err(e) -> rollback_and_checkin(pool, conn, e)
  end
end

fn checkin_and_error(pool, conn, e) do
  safe_checkin(pool, conn)
  Err(e)
end

fn begin_and_run(pool, conn, org_id :: String, query_fn) do
  let begin_result = Pg.begin(conn)
  case begin_result do
    Ok(_) -> set_search_path_and_run(pool, conn, org_id, query_fn)
    Err(e) -> checkin_and_error(pool, conn, e)
  end
end

# Execute a query function within the context of an org's schema.
# Wraps the operation in a transaction with SET LOCAL search_path.
#
# Usage:
#   with_org_schema(pool, org_id, fn(conn) do
#     Pg.execute(conn, "SELECT * FROM projects", [])
#   end)
pub fn with_org_schema(pool, org_id :: String, query_fn) do
  let checkout_result = Pool.checkout(pool)
  case checkout_result do
    Ok(conn) -> begin_and_run(pool, conn, org_id, query_fn)
    Err(e) -> Err(e)
  end
end

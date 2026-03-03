from Org.Schema import provision_org_schema, schema_name_for_org

# Organization HTTP handlers
#
# Provides endpoints for organization CRUD:
#   POST /api/orgs          - Create organization (+ provision schema + add owner membership)
#   GET  /api/orgs          - List user's organizations
#   GET  /api/orgs/:org_id  - Get organization details (members only)
#
# All handlers require an authenticated session. The session cookie is validated
# and user_id is extracted from the sessions table (PG-backed sessions).
#
# Functions MUST be defined before use (no forward references in Mesh).

# ---------------------------------------------------------------------------
# Cookie parsing helpers
# ---------------------------------------------------------------------------

# Recursive helper to find session_id cookie in a list of "key=value" pairs.
fn find_session_at_index(pairs, idx :: Int, len :: Int) -> String!String do
  if idx >= len do
    Err("no session_id cookie")
  else
    let pair = List.get(pairs, idx)
    let is_session = String.starts_with(pair, "session_id=")
    if is_session do
      Ok(String.slice(pair, 11, String.length(pair)))
    else
      find_session_at_index(pairs, idx + 1, len)
    end
  end
end

fn find_session_cookie(cookies :: String) -> String!String do
  let pairs = String.split(cookies, "; ")
  let len = List.length(pairs)
  if len == 0 do
    Err("no session_id cookie")
  else
    find_session_at_index(pairs, 0, len)
  end
end

# ---------------------------------------------------------------------------
# Session validation
# ---------------------------------------------------------------------------

fn validate_session_cookie(pool, session_id :: String) -> String!String do
  let rows = Pool.query(pool, "SELECT user_id FROM sessions WHERE id = $1 AND expires_at > NOW()", [session_id])?
  if List.length(rows) == 0 do
    Err("invalid or expired session")
  else
    Ok(Map.get(List.get(rows, 0), "user_id"))
  end
end

fn extract_user_from_cookies(pool, cookies :: String) -> String!String do
  let session_id = find_session_cookie(cookies)?
  validate_session_cookie(pool, session_id)
end

fn extract_user_id(pool, request) -> String!String do
  let cookie_header = Request.header(request, "cookie")
  case cookie_header do
    None -> Err("no session cookie")
    Some(cookies) -> extract_user_from_cookies(pool, cookies)
  end
end

# ---------------------------------------------------------------------------
# POST /api/orgs helpers (strict bottom-up: leaves first)
# ---------------------------------------------------------------------------

fn rollback_and_error(pool, conn) -> Response do
  let _ = Pg.rollback(conn)
  Pool.checkin(pool, conn)
  HTTP.response(500, json { error: "failed to create organization" })
end

fn finish_provision(pool, conn, org_id :: String, name :: String, schema_name :: String) -> Response do
  Pool.checkin(pool, conn)
  let _ = provision_org_schema(pool, org_id)
  HTTP.response(201, json { id: org_id, name: name, schema_name: schema_name })
end

fn commit_and_provision(pool, conn, org_id :: String, name :: String, schema_name :: String) -> Response do
  let commit_result = Pg.commit(conn)
  case commit_result do
    Err(_) -> rollback_and_error(pool, conn)
    Ok(_) -> finish_provision(pool, conn, org_id, name, schema_name)
  end
end

fn insert_membership(pool, conn, org_id :: String, name :: String, schema_name :: String, membership_id :: String, user_id :: String) -> Response do
  let mem_result = Pg.execute(conn, "INSERT INTO org_memberships (id, org_id, user_id, role) VALUES ($1, $2, $3, 'owner')", [membership_id, org_id, user_id])
  case mem_result do
    Err(_) -> rollback_and_error(pool, conn)
    Ok(_) -> commit_and_provision(pool, conn, org_id, name, schema_name)
  end
end

fn do_insert_org(pool, conn, org_id :: String, name :: String, schema_name :: String, membership_id :: String, user_id :: String) -> Response do
  let insert_result = Pg.execute(conn, "INSERT INTO organizations (id, name, owner_id, schema_name) VALUES ($1, $2, $3, $4)", [org_id, name, user_id, schema_name])
  case insert_result do
    Err(_) -> rollback_and_error(pool, conn)
    Ok(_) -> insert_membership(pool, conn, org_id, name, schema_name, membership_id, user_id)
  end
end

fn begin_create_org(pool, conn, org_id :: String, name :: String, schema_name :: String, membership_id :: String, user_id :: String) -> Response do
  let begin_result = Pg.begin(conn)
  case begin_result do
    Err(_) -> rollback_and_error(pool, conn)
    Ok(_) -> do_insert_org(pool, conn, org_id, name, schema_name, membership_id, user_id)
  end
end

fn execute_create_org(pool, user_id :: String, name :: String) -> Response do
  let org_id = Crypto.uuid4()
  let schema_name = schema_name_for_org(org_id)
  let membership_id = Crypto.uuid4()
  let checkout_result = Pool.checkout(pool)
  case checkout_result do
    Err(_) -> HTTP.response(500, json { error: "database connection failed" })
    Ok(conn) -> begin_create_org(pool, conn, org_id, name, schema_name, membership_id, user_id)
  end
end

fn check_name_max_length(pool, user_id :: String, name :: String, len :: Int) -> Response do
  if len > 100 do
    HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
  else
    execute_create_org(pool, user_id, name)
  end
end

fn create_org_from_json(pool, user_id :: String, body_json) -> Response do
  let name = Json.get(body_json, "name")
  let len = String.length(name)
  if len < 1 do
    HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
  else
    check_name_max_length(pool, user_id, name, len)
  end
end

fn create_org_with_body(pool, user_id :: String, body :: String) -> Response do
  let parsed = Json.parse(body)
  case parsed do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON body" })
    Ok(body_json) -> create_org_from_json(pool, user_id, body_json)
  end
end

fn do_create_org(pool, request, user_id :: String) -> Response do
  let body = Request.body(request)
  create_org_with_body(pool, user_id, body)
end

# ---------------------------------------------------------------------------
# GET /api/orgs helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn format_org_list(rows) -> Response do
  let orgs = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), name: Map.get(row, "name"), schema_name: Map.get(row, "schema_name"), created_at: Map.get(row, "created_at"), role: Map.get(row, "role") }
  end)
  HTTP.response(200, json { organizations: orgs })
end

fn do_list_orgs(pool, user_id :: String) -> Response do
  let query_result = Pool.query(pool, "SELECT o.id, o.name, o.schema_name, o.created_at, m.role FROM organizations o JOIN org_memberships m ON o.id = m.org_id WHERE m.user_id = $1 ORDER BY o.created_at", [user_id])
  case query_result do
    Err(_) -> HTTP.response(500, json { error: "failed to list organizations" })
    Ok(rows) -> format_org_list(rows)
  end
end

# ---------------------------------------------------------------------------
# GET /api/orgs/:org_id helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn build_org_response(org, role :: String) -> Response do
  HTTP.response(200, json { id: Map.get(org, "id"), name: Map.get(org, "name"), owner_id: Map.get(org, "owner_id"), schema_name: Map.get(org, "schema_name"), created_at: Map.get(org, "created_at"), role: role })
end

fn check_org_exists(org_rows, role :: String) -> Response do
  let org_count = List.length(org_rows)
  if org_count == 0 do
    HTTP.response(404, json { error: "organization not found" })
  else
    build_org_response(List.get(org_rows, 0), role)
  end
end

fn fetch_org_details(pool, org_id :: String, role :: String) -> Response do
  let org_result = Pool.query(pool, "SELECT id, name, owner_id, schema_name, created_at FROM organizations WHERE id = $1", [org_id])
  case org_result do
    Err(_) -> HTTP.response(500, json { error: "failed to fetch organization" })
    Ok(org_rows) -> check_org_exists(org_rows, role)
  end
end

fn check_membership_result(pool, org_id :: String, mem_rows) -> Response do
  let mem_count = List.length(mem_rows)
  if mem_count == 0 do
    HTTP.response(403, json { error: "not a member of this organization" })
  else
    fetch_org_details(pool, org_id, Map.get(List.get(mem_rows, 0), "role"))
  end
end

fn check_membership(pool, org_id :: String, user_id :: String) -> Response do
  let mem_result = Pool.query(pool, "SELECT role FROM org_memberships WHERE org_id = $1 AND user_id = $2", [org_id, user_id])
  case mem_result do
    Err(_) -> HTTP.response(500, json { error: "failed to check membership" })
    Ok(mem_rows) -> check_membership_result(pool, org_id, mem_rows)
  end
end

fn do_get_org(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> check_membership(pool, org_id, user_id)
  end
end

# ---------------------------------------------------------------------------
# Public handler entry points
# ---------------------------------------------------------------------------

# POST /api/orgs
pub fn handle_create_org(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_create_org(pool, request, user_id)
  end
end

# GET /api/orgs
pub fn handle_list_orgs(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_list_orgs(pool, user_id)
  end
end

# GET /api/orgs/:org_id
pub fn handle_get_org(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_get_org(pool, request, user_id)
  end
end

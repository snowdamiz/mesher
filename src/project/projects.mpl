# Project management and API key handlers (ORG-04, ORG-05)
#
# Provides endpoints for project CRUD and API key management:
#   POST /api/orgs/:org_id/projects                        - Create project
#   GET  /api/orgs/:org_id/projects                        - List projects
#   POST /api/orgs/:org_id/projects/:project_id/api-keys   - Create API key
#   GET  /api/orgs/:org_id/projects/:project_id/api-keys   - List API keys
#   POST /api/orgs/:org_id/api-keys/:key_id/revoke         - Revoke API key
#
# All operations are tenant-scoped via with_org_schema from db/tenant.mpl.
# API keys: raw key shown once on creation, stored as SHA-256 hash.
#
# Functions MUST be defined before use (no forward references).
# Case arm expressions MUST be on same line as -> (no multi-line bodies).

import Db.Tenant

# ---------------------------------------------------------------------------
# Cookie parsing helpers (duplicated per Mesh constraint)
# ---------------------------------------------------------------------------

fn find_session_at_index_proj(pairs, idx :: Int, len :: Int) -> String!String do
  if idx >= len do
    Err("no session_id cookie")
  else
    let pair = List.get(pairs, idx)
    let is_session = String.starts_with(pair, "session_id=")
    if is_session do
      Ok(String.slice(pair, 11, String.length(pair)))
    else
      find_session_at_index_proj(pairs, idx + 1, len)
    end
  end
end

fn find_session_cookie_proj(cookies :: String) -> String!String do
  let pairs = String.split(cookies, "; ")
  let len = List.length(pairs)
  if len == 0 do
    Err("no session_id cookie")
  else
    find_session_at_index_proj(pairs, 0, len)
  end
end

fn validate_session_cookie_proj(pool, session_id :: String) -> String!String do
  let rows = Pool.query(pool, "SELECT user_id FROM sessions WHERE id = $1 AND expires_at > NOW()", [session_id])?
  let count = List.length(rows)
  if count == 0 do
    Err("invalid or expired session")
  else
    Ok(Map.get(List.get(rows, 0), "user_id"))
  end
end

fn extract_user_from_cookies_proj(pool, cookies :: String) -> String!String do
  let session_id = find_session_cookie_proj(cookies)?
  validate_session_cookie_proj(pool, session_id)
end

fn extract_user_id_proj(pool, request) -> String!String do
  let cookie_header = Request.header(request, "cookie")
  case cookie_header do
    None -> Err("no session cookie")
    Some(cookies) -> extract_user_from_cookies_proj(pool, cookies)
  end
end

# ---------------------------------------------------------------------------
# Membership check helper (leaf first)
# ---------------------------------------------------------------------------

fn check_membership_proj_count(mem_rows) -> Int!String do
  let count = List.length(mem_rows)
  if count == 0 do
    Err("not a member")
  else
    Ok(0)
  end
end

fn check_membership_proj(pool, org_id :: String, user_id :: String) -> Int!String do
  let mem_result = Pool.query(pool, "SELECT role FROM org_memberships WHERE org_id = $1 AND user_id = $2", [org_id, user_id])
  case mem_result do
    Err(e) -> Err(e)
    Ok(mem_rows) -> check_membership_proj_count(mem_rows)
  end
end

# ---------------------------------------------------------------------------
# POST /api/orgs/:org_id/projects helpers (strict bottom-up: leaves first)
# ---------------------------------------------------------------------------

fn insert_project(pool, org_id :: String, name :: String, project_id :: String) -> Response do
  let insert_result = Tenant.with_org_schema(pool, org_id, fn(conn) do
    Pg.execute(conn, "INSERT INTO projects (id, name) VALUES ($1, $2)", [project_id, name])
  end)
  case insert_result do
    Err(_) -> HTTP.response(500, json { error: "failed to create project" })
    Ok(_) -> HTTP.response(201, json { id: project_id, name: name })
  end
end

fn create_project_in_schema(pool, org_id :: String, name :: String) -> Response do
  let id_result = Pool.query(pool, "SELECT gen_random_uuid()::text AS project_id", [])
  case id_result do
    Err(_) -> HTTP.response(500, json { error: "failed to generate project ID" })
    Ok(id_rows) -> insert_project(pool, org_id, name, Map.get(List.head(id_rows), "project_id"))
  end
end

fn validate_project_name_max(pool, org_id :: String, name :: String, len :: Int) -> Response do
  if len > 100 do
    HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
  else
    create_project_in_schema(pool, org_id, name)
  end
end

fn parse_project_body(pool, org_id :: String, body_json) -> Response do
  let name = Json.get(body_json, "name")
  let len = String.length(name)
  if len < 1 do
    HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
  else
    validate_project_name_max(pool, org_id, name, len)
  end
end

fn parse_project_request_body(pool, org_id :: String, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body_json) -> parse_project_body(pool, org_id, body_json)
  end
end

fn create_project_with_org(pool, org_id :: String, user_id :: String, request) -> Response do
  let mem_check = check_membership_proj(pool, org_id, user_id)
  case mem_check do
    Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
    Ok(_) -> parse_project_request_body(pool, org_id, request)
  end
end

fn do_create_project(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> create_project_with_org(pool, org_id, user_id, request)
  end
end

# POST /api/orgs/:org_id/projects
pub fn create_project_handler(pool, request) -> Response do
  let user_result = extract_user_id_proj(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_create_project(pool, request, user_id)
  end
end

# ---------------------------------------------------------------------------
# GET /api/orgs/:org_id/projects helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn format_project_list(rows) -> Response do
  let projects = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), name: Map.get(row, "name"), created_at: Map.get(row, "created_at") }
  end)
  HTTP.response(200, json { projects: projects })
end

fn query_projects(pool, org_id :: String) -> Response do
  let query_result = Tenant.with_org_schema(pool, org_id, fn(conn) do
    Pg.query(conn, "SELECT id, name, created_at FROM projects ORDER BY created_at", [])
  end)
  case query_result do
    Err(_) -> HTTP.response(500, json { error: "failed to list projects" })
    Ok(rows) -> format_project_list(rows)
  end
end

fn list_projects_with_org(pool, org_id :: String, user_id :: String) -> Response do
  let mem_check = check_membership_proj(pool, org_id, user_id)
  case mem_check do
    Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
    Ok(_) -> query_projects(pool, org_id)
  end
end

fn do_list_projects(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> list_projects_with_org(pool, org_id, user_id)
  end
end

# GET /api/orgs/:org_id/projects
pub fn list_projects_handler(pool, request) -> Response do
  let user_result = extract_user_id_proj(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_list_projects(pool, request, user_id)
  end
end

# ---------------------------------------------------------------------------
# POST /api/orgs/:org_id/projects/:project_id/api-keys helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn build_dsn(key_prefix :: String, raw_key :: String, project_id :: String) -> String do
  let host = Env.get("APP_URL", "http://localhost:8080")
  host <> "/api/" <> project_id <> "/"
end

fn insert_api_key(pool, org_id :: String, project_id :: String, label :: String, raw_key :: String, key_prefix :: String, key_hash :: String, key_id :: String) -> Response do
  let insert_result = Tenant.with_org_schema(pool, org_id, fn(conn) do
    Pg.execute(conn, "INSERT INTO api_keys (id, project_id, key_hash, key_prefix, label) VALUES ($1, $2, $3, $4, $5)", [key_id, project_id, key_hash, key_prefix, label])
  end)
  case insert_result do
    Err(_) -> HTTP.response(500, json { error: "failed to create API key" })
    Ok(_) -> HTTP.response(201, json { id: key_id, key: raw_key, prefix: key_prefix, dsn: build_dsn(key_prefix, raw_key, project_id) })
  end
end

fn hash_and_insert_key(pool, org_id :: String, project_id :: String, label :: String, raw_key :: String, key_id :: String) -> Response do
  let key_prefix = String.slice(raw_key, 0, 8)
  let hash_result = Pool.query(pool, "SELECT encode(digest($1, 'sha256'), 'hex') AS key_hash", [raw_key])
  case hash_result do
    Err(_) -> HTTP.response(500, json { error: "failed to hash API key" })
    Ok(hash_rows) -> insert_api_key(pool, org_id, project_id, label, raw_key, key_prefix, Map.get(List.head(hash_rows), "key_hash"), key_id)
  end
end

fn generate_api_key(pool, org_id :: String, project_id :: String, label :: String) -> Response do
  let gen_result = Pool.query(pool, "SELECT gen_random_uuid()::text AS raw_key, gen_random_uuid()::text AS key_id", [])
  case gen_result do
    Err(_) -> HTTP.response(500, json { error: "failed to generate API key" })
    Ok(gen_rows) -> hash_and_insert_key(pool, org_id, project_id, label, Map.get(List.head(gen_rows), "raw_key"), Map.get(List.head(gen_rows), "key_id"))
  end
end

fn parse_api_key_body(pool, org_id :: String, project_id :: String, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> generate_api_key(pool, org_id, project_id, "")
    Ok(body_json) -> generate_api_key(pool, org_id, project_id, Json.get(body_json, "label"))
  end
end

fn extract_project_id_for_key(pool, org_id :: String, request) -> Response do
  let project_id_opt = Request.param(request, "project_id")
  case project_id_opt do
    None -> HTTP.response(400, json { error: "missing project_id parameter" })
    Some(project_id) -> parse_api_key_body(pool, org_id, project_id, request)
  end
end

fn create_key_with_project(pool, org_id :: String, user_id :: String, request) -> Response do
  let mem_check = check_membership_proj(pool, org_id, user_id)
  case mem_check do
    Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
    Ok(_) -> extract_project_id_for_key(pool, org_id, request)
  end
end

fn do_create_api_key(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> create_key_with_project(pool, org_id, user_id, request)
  end
end

# POST /api/orgs/:org_id/projects/:project_id/api-keys
pub fn create_api_key_handler(pool, request) -> Response do
  let user_result = extract_user_id_proj(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_create_api_key(pool, request, user_id)
  end
end

# ---------------------------------------------------------------------------
# POST /api/orgs/:org_id/api-keys/:key_id/revoke helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn do_revoke_key(pool, org_id :: String, key_id :: String) -> Response do
  let revoke_result = Tenant.with_org_schema(pool, org_id, fn(conn) do
    Pg.execute(conn, "UPDATE api_keys SET revoked_at = NOW() WHERE id = $1 AND revoked_at IS NULL", [key_id])
  end)
  case revoke_result do
    Err(_) -> HTTP.response(500, json { error: "failed to revoke API key" })
    Ok(_) -> HTTP.response(200, json { status: "API key revoked" })
  end
end

fn extract_key_id_for_revoke(pool, org_id :: String, request) -> Response do
  let key_id_opt = Request.param(request, "key_id")
  case key_id_opt do
    None -> HTTP.response(400, json { error: "missing key_id parameter" })
    Some(key_id) -> do_revoke_key(pool, org_id, key_id)
  end
end

fn revoke_key_with_org(pool, org_id :: String, user_id :: String, request) -> Response do
  let mem_check = check_membership_proj(pool, org_id, user_id)
  case mem_check do
    Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
    Ok(_) -> extract_key_id_for_revoke(pool, org_id, request)
  end
end

fn do_revoke_api_key(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> revoke_key_with_org(pool, org_id, user_id, request)
  end
end

# POST /api/orgs/:org_id/api-keys/:key_id/revoke
pub fn revoke_api_key_handler(pool, request) -> Response do
  let user_result = extract_user_id_proj(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_revoke_api_key(pool, request, user_id)
  end
end

# ---------------------------------------------------------------------------
# GET /api/orgs/:org_id/projects/:project_id/api-keys helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn format_api_key_list(rows) -> Response do
  let keys = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), project_id: Map.get(row, "project_id"), key_prefix: Map.get(row, "key_prefix"), label: Map.get(row, "label"), created_at: Map.get(row, "created_at"), revoked_at: Map.get(row, "revoked_at") }
  end)
  HTTP.response(200, json { api_keys: keys })
end

fn query_api_keys(pool, org_id :: String, project_id :: String) -> Response do
  let query_result = Tenant.with_org_schema(pool, org_id, fn(conn) do
    Pg.query(conn, "SELECT id, project_id, key_prefix, label, created_at, revoked_at FROM api_keys WHERE project_id = $1 ORDER BY created_at DESC", [project_id])
  end)
  case query_result do
    Err(_) -> HTTP.response(500, json { error: "failed to list API keys" })
    Ok(rows) -> format_api_key_list(rows)
  end
end

fn extract_project_id_for_list(pool, org_id :: String, request) -> Response do
  let project_id_opt = Request.param(request, "project_id")
  case project_id_opt do
    None -> HTTP.response(400, json { error: "missing project_id parameter" })
    Some(project_id) -> query_api_keys(pool, org_id, project_id)
  end
end

fn list_keys_with_project(pool, org_id :: String, user_id :: String, request) -> Response do
  let mem_check = check_membership_proj(pool, org_id, user_id)
  case mem_check do
    Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
    Ok(_) -> extract_project_id_for_list(pool, org_id, request)
  end
end

fn do_list_api_keys(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> list_keys_with_project(pool, org_id, user_id, request)
  end
end

# GET /api/orgs/:org_id/projects/:project_id/api-keys
pub fn list_api_keys_handler(pool, request) -> Response do
  let user_result = extract_user_id_proj(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_list_api_keys(pool, request, user_id)
  end
end

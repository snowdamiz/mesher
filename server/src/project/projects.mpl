# Project management and API key handlers
#
# Provides endpoints for project CRUD and API key management:
#   POST /api/orgs/:org_id/projects                        - Create project
#   GET  /api/orgs/:org_id/projects                        - List projects
#   POST /api/orgs/:org_id/projects/:project_id/api-keys   - Create API key
#   GET  /api/orgs/:org_id/projects/:project_id/api-keys   - List API keys
#   POST /api/orgs/:org_id/api-keys/:key_id/revoke         - Revoke API key
#
# All data access via centralized storage/queries.mpl ORM functions.
# API keys: raw key shown once on creation, stored as SHA-256 hash.

from Src.Auth.Guards import require_member, require_project_member, require_param, parse_json_body, validate_name, guard_error
from Src.Storage.Queries import create_project, list_projects, create_api_key, list_api_keys, revoke_api_key

# POST /api/orgs/:org_id/projects
pub fn create_project_handler(pool, request) -> Response do
  case do_create_project(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_create_project(pool, request) -> Response!String do
  let mem = require_member(pool, request)?
  let org_id = Map.get(mem, "org_id")
  let body_json = parse_json_body(request)?
  let name = Json.get(body_json, "name")
  let _ = validate_name(name)?
  let project_id = create_project(pool, org_id, name)?
  Ok(HTTP.response(201, json { id: project_id, name: name }))
end

# GET /api/orgs/:org_id/projects
pub fn list_projects_handler(pool, request) -> Response do
  case do_list_projects(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_list_projects(pool, request) -> Response!String do
  let mem = require_member(pool, request)?
  let org_id = Map.get(mem, "org_id")
  let rows = list_projects(pool, org_id)?
  let projects = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), name: Map.get(row, "name"), created_at: Map.get(row, "created_at") }
  end)
  Ok(HTTP.response(200, json { projects: projects }))
end

# POST /api/orgs/:org_id/projects/:project_id/api-keys
pub fn create_api_key_handler(pool, request) -> Response do
  case do_create_api_key(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_create_api_key(pool, request) -> Response!String do
  let pm = require_project_member(pool, request)?
  let project_id = Map.get(pm, "project_id")
  let raw_body = Request.body(request)
  let label = case Json.parse(raw_body) do
    Err(_) -> ""
    Ok(body_json) -> Json.get(body_json, "label")
  end
  let raw_key = Crypto.uuid4()
  let key_prefix = String.slice(raw_key, 0, 8)
  let key_hash = Crypto.sha256(raw_key)
  let key_id = create_api_key(pool, project_id, key_hash, key_prefix, label)?
  let host = Env.get("APP_URL", "http://localhost:8080")
  let dsn = host <> "/api/" <> project_id <> "/"
  Ok(HTTP.response(201, json { id: key_id, key: raw_key, prefix: key_prefix, dsn: dsn }))
end

# GET /api/orgs/:org_id/projects/:project_id/api-keys
pub fn list_api_keys_handler(pool, request) -> Response do
  case do_list_api_keys(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_list_api_keys(pool, request) -> Response!String do
  let pm = require_project_member(pool, request)?
  let project_id = Map.get(pm, "project_id")
  let rows = list_api_keys(pool, project_id)?
  let keys = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), project_id: Map.get(row, "project_id"), key_prefix: Map.get(row, "key_prefix"), label: Map.get(row, "label"), created_at: Map.get(row, "created_at"), revoked_at: Map.get(row, "revoked_at") }
  end)
  Ok(HTTP.response(200, json { api_keys: keys }))
end

# POST /api/orgs/:org_id/api-keys/:key_id/revoke
pub fn revoke_api_key_handler(pool, request) -> Response do
  case do_revoke_api_key(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_revoke_api_key(pool, request) -> Response!String do
  let mem = require_member(pool, request)?
  let key_id = require_param(request, "key_id")?
  let _ = revoke_api_key(pool, key_id)?
  Ok(HTTP.response(200, json { status: "API key revoked" }))
end

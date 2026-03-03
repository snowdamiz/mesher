from Src.Auth.Cookies import extract_user_id
from Src.Auth.Guards import require_member, parse_json_body, validate_name, guard_error
from Src.Storage.Queries import insert_org, get_org, list_user_orgs, add_member

# Organization HTTP handlers
#
# Provides endpoints for organization CRUD:
#   POST /api/orgs          - Create organization (+ add owner membership)
#   GET  /api/orgs          - List user's organizations
#   GET  /api/orgs/:org_id  - Get organization details (members only)
#
# All handlers require an authenticated session via Auth.Cookies.
# All data access via centralized storage/queries.mpl ORM functions.

# POST /api/orgs
pub fn handle_create_org(pool, request) -> Response do
  case do_create_org(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_create_org(pool, request) -> Response!String do
  let user_id = extract_user_id(pool, request)?
  let body_json = parse_json_body(request)?
  let name = Json.get(body_json, "name")
  let _ = validate_name(name)?
  let slug = String.replace(String.lower(name), " ", "-")
  let org_id = insert_org(pool, name, slug)?
  let _ = add_member(pool, org_id, user_id, "owner")?
  Ok(HTTP.response(201, json { id: org_id, name: name, slug: slug }))
end

# GET /api/orgs
pub fn handle_list_orgs(pool, request) -> Response do
  case do_list_orgs(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_list_orgs(pool, request) -> Response!String do
  let user_id = extract_user_id(pool, request)?
  let rows = list_user_orgs(pool, user_id)?
  let orgs = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), name: Map.get(row, "name"), slug: Map.get(row, "slug"), created_at: Map.get(row, "created_at"), role: Map.get(row, "role") }
  end)
  Ok(HTTP.response(200, json { organizations: orgs }))
end

# GET /api/orgs/:org_id
pub fn handle_get_org(pool, request) -> Response do
  case do_get_org(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_get_org(pool, request) -> Response!String do
  let mem = require_member(pool, request)?
  let org_id = Map.get(mem, "org_id")
  let role = Map.get(mem, "role")
  let org = get_org(pool, org_id)?
  Ok(HTTP.response(200, json { id: Map.get(org, "id"), name: Map.get(org, "name"), slug: Map.get(org, "slug"), created_at: Map.get(org, "created_at"), role: role }))
end

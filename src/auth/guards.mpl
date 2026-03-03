# Shared guard functions for request validation.
# Converts common Option/Result checks into chainable Result types
# so handlers can use the ? operator to flatten nesting.
#
# Used by: Org.Handlers, Org.Invites, Project.Projects, Auth.Oauth

from Src.Auth.Cookies import extract_user_id
from Src.Storage.Queries import check_membership

# Convert Request.param Option to Result.
pub fn require_param(request, name :: String) -> String!String do
  case Request.param(request, name) do
    None -> Err("missing " <> name <> " parameter")
    Some(value) -> Ok(value)
  end
end

# Convert Request.query Option to Result.
pub fn require_query(request, name :: String) -> String!String do
  case Request.query(request, name) do
    None -> Err("missing " <> name <> " parameter")
    Some(value) -> Ok(value)
  end
end

# Parse request body as JSON.
pub fn parse_json_body(request) do
  let body = Request.body(request)
  case Json.parse(body) do
    Err(_) -> Err("invalid JSON body")
    Ok(parsed) -> Ok(parsed)
  end
end

# Require authenticated user + org membership.
# Returns map with "user_id", "org_id", "role".
pub fn require_member(pool, request) -> Map<String, String>!String do
  let user_id = extract_user_id(pool, request)?
  let org_id = require_param(request, "org_id")?
  let membership = check_membership(pool, org_id, user_id)?
  let role = Map.get(membership, "role")
  Ok(%{"user_id" => user_id, "org_id" => org_id, "role" => role})
end

# Require authenticated user + org ownership.
# Returns map with "user_id", "org_id", "role".
pub fn require_owner(pool, request) -> Map<String, String>!String do
  let mem = require_member(pool, request)?
  let role = Map.get(mem, "role")
  if role == "owner" do
    Ok(mem)
  else
    Err("owner required")
  end
end

# Require authenticated user + org membership + project_id param.
# Returns map with "user_id", "org_id", "role", "project_id".
pub fn require_project_member(pool, request) -> Map<String, String>!String do
  let mem = require_member(pool, request)?
  let project_id = require_param(request, "project_id")?
  Ok(%{"user_id" => Map.get(mem, "user_id"), "org_id" => Map.get(mem, "org_id"), "role" => Map.get(mem, "role"), "project_id" => project_id})
end

# Validate name is between 1 and 100 characters.
pub fn validate_name(name :: String) -> String!String do
  let len = String.length(name)
  if len < 1 do
    Err("name must be between 1 and 100 characters")
  else if len > 100 do
    Err("name must be between 1 and 100 characters")
  else
    Ok(name)
  end
end

# Map error strings from guards to HTTP responses.
pub fn guard_error(msg :: String) -> Response do
  if msg == "no session cookie" do
    HTTP.response(401, json { error: "unauthorized" })
  else if msg == "not a member" do
    HTTP.response(403, json { error: "not a member of this organization" })
  else if msg == "owner required" do
    HTTP.response(403, json { error: "owner required" })
  else if msg == "not found" do
    HTTP.response(404, json { error: "not found" })
  else if String.starts_with(msg, "missing ") or String.starts_with(msg, "invalid ") or String.starts_with(msg, "name must") do
    HTTP.response(400, json { error: msg })
  else if String.starts_with(msg, "user is already") or String.starts_with(msg, "invite already") do
    HTTP.response(409, json { error: msg })
  else
    HTTP.response(500, json { error: msg })
  end
end

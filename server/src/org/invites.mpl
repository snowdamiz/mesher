from Src.Mail.Sender import send_email
from Src.Auth.Cookies import extract_user_id
from Src.Auth.Guards import require_owner, require_member, require_param, parse_json_body, guard_error
from Src.Storage.Queries import get_org, create_invite, get_pending_invite, check_pending_invite_by_email, check_existing_member_by_email, accept_invite, add_member, revoke_invite, list_invites

# Organization invite handlers
#
# Provides endpoints for organization invitations:
#   POST   /api/orgs/:org_id/invites             - Create invite (owner only)
#   GET    /api/orgs/:org_id/invites             - List invites (members)
#   POST   /api/orgs/:org_id/invites/:invite_id/revoke - Revoke invite (owner only)
#   POST   /api/invites/:token/accept            - Accept invite (auth required)
#
# All data access via centralized storage/queries.mpl ORM functions.

fn send_invite_email(email :: String, token :: String, org_name :: String) -> Response do
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let invite_url = app_url <> "/invites/" <> token <> "/accept"
  let body_text = "You have been invited to " <> org_name <> " on Mesher. Accept invite: " <> invite_url
  let _ = send_email(email, "You've been invited to " <> org_name <> " on Mesher", body_text)
  HTTP.response(201, json { email: email, token: token })
end

fn validate_invite_eligibility(pool, org_id :: String, email :: String) -> String!String do
  let org = get_org(pool, org_id)?
  let org_name = Map.get(org, "name")
  let already_member = check_existing_member_by_email(pool, org_id, email)?
  if already_member do
    Err("user is already a member")
  else
    let pending = check_pending_invite_by_email(pool, org_id, email)?
    if pending do
      Err("invite already pending")
    else
      Ok(org_name)
    end
  end
end

# POST /api/orgs/:org_id/invites
pub fn create_invite_handler(pool, request) -> Response do
  case do_create_invite(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_create_invite(pool, request) -> Response!String do
  let mem = require_owner(pool, request)?
  let org_id = Map.get(mem, "org_id")
  let user_id = Map.get(mem, "user_id")
  let body_json = parse_json_body(request)?
  let email = Json.get(body_json, "email")
  let org_name = validate_invite_eligibility(pool, org_id, email)?
  let token = Crypto.uuid4()
  let _ = create_invite(pool, org_id, email, token, user_id)?
  Ok(send_invite_email(email, token, org_name))
end

# POST /api/invites/:token/accept
pub fn accept_invite_handler(pool, request) -> Response do
  case do_accept_invite(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_accept_invite(pool, request) -> Response!String do
  let token = require_param(request, "token")?
  let user_id = extract_user_id(pool, request)?
  let invite = get_pending_invite(pool, token)?
  let invite_id = Map.get(invite, "id")
  let org_id = Map.get(invite, "org_id")
  let _ = add_member(pool, org_id, user_id, "member")?
  let _ = accept_invite(pool, invite_id)
  Ok(HTTP.response(200, json { status: "joined", org_id: org_id }))
end

# POST /api/orgs/:org_id/invites/:invite_id/revoke
pub fn revoke_invite_handler(pool, request) -> Response do
  case do_revoke_invite(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_revoke_invite(pool, request) -> Response!String do
  let mem = require_owner(pool, request)?
  let org_id = Map.get(mem, "org_id")
  let invite_id = require_param(request, "invite_id")?
  let _ = revoke_invite(pool, invite_id, org_id)?
  Ok(HTTP.response(200, json { status: "invite revoked" }))
end

# GET /api/orgs/:org_id/invites
pub fn list_invites_handler(pool, request) -> Response do
  case do_list_invites(pool, request) do
    Err(e) -> guard_error(e)
    Ok(r) -> r
  end
end

fn do_list_invites(pool, request) -> Response!String do
  let mem = require_member(pool, request)?
  let org_id = Map.get(mem, "org_id")
  let rows = list_invites(pool, org_id)?
  let invites = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), email: Map.get(row, "email"), expires_at: Map.get(row, "expires_at"), accepted_at: Map.get(row, "accepted_at"), revoked_at: Map.get(row, "revoked_at"), created_at: Map.get(row, "created_at") }
  end)
  Ok(HTTP.response(200, json { invites: invites }))
end

from Mail.Sender import send_email

# Organization invite handlers (ORG-02, ORG-03)
#
# Provides endpoints for organization invitations:
#   POST   /api/orgs/:org_id/invites             - Create invite (owner only)
#   GET    /api/orgs/:org_id/invites             - List invites (members)
#   DELETE /api/orgs/:org_id/invites/:invite_id  - Revoke invite (owner only)
#   POST   /api/invites/:token/accept            - Accept invite (auth or unauth)
#
# Functions MUST be defined before use (no forward references).
# Case arm expressions MUST be on same line as -> (no multi-line bodies).

# ---------------------------------------------------------------------------
# Cookie parsing helpers (local to this module)
# ---------------------------------------------------------------------------

fn find_session_at_index_inv(pairs, idx :: Int, len :: Int) -> String!String do
  if idx >= len do
    Err("no session_id cookie")
  else
    let pair = List.get(pairs, idx)
    let is_session = String.starts_with(pair, "session_id=")
    if is_session do
      Ok(String.slice(pair, 11, String.length(pair)))
    else
      find_session_at_index_inv(pairs, idx + 1, len)
    end
  end
end

fn find_session_cookie_inv(cookies :: String) -> String!String do
  let pairs = String.split(cookies, "; ")
  let len = List.length(pairs)
  if len == 0 do
    Err("no session_id cookie")
  else
    find_session_at_index_inv(pairs, 0, len)
  end
end

fn validate_session_cookie_inv(pool, session_id :: String) -> String!String do
  let rows = Pool.query(pool, "SELECT user_id FROM sessions WHERE id = $1 AND expires_at > NOW()", [session_id])?
  let count = List.length(rows)
  if count == 0 do
    Err("invalid or expired session")
  else
    Ok(Map.get(List.get(rows, 0), "user_id"))
  end
end

fn extract_user_from_cookies_inv(pool, cookies :: String) -> String!String do
  let session_id = find_session_cookie_inv(cookies)?
  validate_session_cookie_inv(pool, session_id)
end

fn extract_user_id_inv(pool, request) -> String!String do
  let cookie_header = Request.header(request, "cookie")
  case cookie_header do
    None -> Err("no session cookie")
    Some(cookies) -> extract_user_from_cookies_inv(pool, cookies)
  end
end

# ---------------------------------------------------------------------------
# POST /api/orgs/:org_id/invites helpers (strict bottom-up: deepest leaves first)
# ---------------------------------------------------------------------------

fn send_invite_email(email :: String, token :: String, org_name :: String) -> Response do
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let invite_url = app_url <> "/invites/" <> token <> "/accept"
  let body_text = "You have been invited to " <> org_name <> " on Mesher. Accept invite: " <> invite_url
  let _ = send_email(email, "You've been invited to " <> org_name <> " on Mesher", body_text)
  HTTP.response(201, json { email: email, token: token })
end

fn do_insert_invite(pool, org_id :: String, email :: String, user_id :: String, org_name :: String, invite_id :: String, token :: String) -> Response do
  let insert_result = Pool.execute(pool, "INSERT INTO invites (id, org_id, email, token, invited_by, expires_at) VALUES ($1, $2, $3, $4, $5, NOW() + INTERVAL '7 days')", [invite_id, org_id, email, token, user_id])
  case insert_result do
    Err(_) -> HTTP.response(500, json { error: "failed to create invite" })
    Ok(_) -> send_invite_email(email, token, org_name)
  end
end

fn insert_invite(pool, org_id :: String, email :: String, user_id :: String, org_name :: String) -> Response do
  let invite_id = Crypto.uuid4()
  let token = Crypto.uuid4()
  do_insert_invite(pool, org_id, email, user_id, org_name, invite_id, token)
end

fn check_pending_count(pool, org_id :: String, email :: String, user_id :: String, org_name :: String, pending_rows) -> Response do
  let pending_count = List.length(pending_rows)
  if pending_count > 0 do
    HTTP.response(409, json { error: "invite already pending" })
  else
    insert_invite(pool, org_id, email, user_id, org_name)
  end
end

fn check_pending_invite(pool, org_id :: String, email :: String, user_id :: String, org_name :: String) -> Response do
  let pending_result = Pool.query(pool, "SELECT id FROM invites WHERE org_id = $1 AND email = $2 AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > NOW()", [org_id, email])
  case pending_result do
    Err(_) -> HTTP.response(500, json { error: "failed to check pending invites" })
    Ok(pending_rows) -> check_pending_count(pool, org_id, email, user_id, org_name, pending_rows)
  end
end

fn check_existing_member_count(pool, org_id :: String, email :: String, user_id :: String, org_name :: String, mem_rows) -> Response do
  let mem_count = List.length(mem_rows)
  if mem_count > 0 do
    HTTP.response(409, json { error: "user is already a member" })
  else
    check_pending_invite(pool, org_id, email, user_id, org_name)
  end
end

fn check_existing_member(pool, org_id :: String, email :: String, user_id :: String, org_name :: String) -> Response do
  let mem_result = Pool.query(pool, "SELECT m.id FROM org_memberships m JOIN users u ON m.user_id = u.id WHERE m.org_id = $1 AND u.email = $2", [org_id, email])
  case mem_result do
    Err(_) -> HTTP.response(500, json { error: "failed to check membership" })
    Ok(mem_rows) -> check_existing_member_count(pool, org_id, email, user_id, org_name, mem_rows)
  end
end

fn check_org_found(pool, org_id :: String, email :: String, user_id :: String, org_rows) -> Response do
  let org_count = List.length(org_rows)
  if org_count == 0 do
    HTTP.response(404, json { error: "organization not found" })
  else
    check_existing_member(pool, org_id, email, user_id, Map.get(List.head(org_rows), "name"))
  end
end

fn get_org_name_and_invite(pool, org_id :: String, email :: String, user_id :: String) -> Response do
  let org_result = Pool.query(pool, "SELECT name FROM organizations WHERE id = $1", [org_id])
  case org_result do
    Err(_) -> HTTP.response(500, json { error: "failed to fetch organization" })
    Ok(org_rows) -> check_org_found(pool, org_id, email, user_id, org_rows)
  end
end

fn check_is_owner(pool, org_id :: String, email :: String, user_id :: String, role :: String) -> Response do
  if role != "owner" do
    HTTP.response(403, json { error: "only owners can create invites" })
  else
    get_org_name_and_invite(pool, org_id, email, user_id)
  end
end

fn check_owner_role(pool, org_id :: String, email :: String, user_id :: String, role_rows) -> Response do
  let role_count = List.length(role_rows)
  if role_count == 0 do
    HTTP.response(403, json { error: "not a member of this organization" })
  else
    check_is_owner(pool, org_id, email, user_id, Map.get(List.head(role_rows), "role"))
  end
end

fn verify_owner_and_invite(pool, org_id :: String, email :: String, user_id :: String) -> Response do
  let role_result = Pool.query(pool, "SELECT role FROM org_memberships WHERE org_id = $1 AND user_id = $2", [org_id, user_id])
  case role_result do
    Err(_) -> HTTP.response(500, json { error: "failed to check role" })
    Ok(role_rows) -> check_owner_role(pool, org_id, email, user_id, role_rows)
  end
end

fn parse_invite_body(pool, org_id :: String, user_id :: String, body_json) -> Response do
  let email = Json.get(body_json, "email")
  verify_owner_and_invite(pool, org_id, email, user_id)
end

fn create_invite_with_org(pool, org_id :: String, user_id :: String, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body_json) -> parse_invite_body(pool, org_id, user_id, body_json)
  end
end

fn do_create_invite(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> create_invite_with_org(pool, org_id, user_id, request)
  end
end

# POST /api/orgs/:org_id/invites
pub fn create_invite_handler(pool, request) -> Response do
  let user_result = extract_user_id_inv(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_create_invite(pool, request, user_id)
  end
end

# ---------------------------------------------------------------------------
# POST /api/invites/:token/accept helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn mark_invite_accepted(pool, invite_id :: String, org_id :: String) -> Response do
  let _ = Pool.execute(pool, "UPDATE invites SET accepted_at = NOW() WHERE id = $1", [invite_id])
  HTTP.response(200, json { status: "joined", org_id: org_id })
end

fn insert_membership_and_accept(pool, invite_id :: String, org_id :: String, user_id :: String, mem_id :: String) -> Response do
  let mem_result = Pool.execute(pool, "INSERT INTO org_memberships (id, org_id, user_id, role) VALUES ($1, $2, $3, 'member')", [mem_id, org_id, user_id])
  case mem_result do
    Err(_) -> HTTP.response(500, json { error: "failed to join organization" })
    Ok(_) -> mark_invite_accepted(pool, invite_id, org_id)
  end
end

fn complete_accept(pool, invite_id :: String, org_id :: String, user_id :: String) -> Response do
  let mem_id = Crypto.uuid4()
  insert_membership_and_accept(pool, invite_id, org_id, user_id, mem_id)
end

fn check_invite_found(pool, invite_rows, user_id :: String) -> Response do
  let count = List.length(invite_rows)
  if count == 0 do
    HTTP.response(400, json { error: "invalid or expired invite" })
  else
    complete_accept(pool, Map.get(List.head(invite_rows), "id"), Map.get(List.head(invite_rows), "org_id"), user_id)
  end
end

fn lookup_invite_for_accept(pool, token :: String, user_id :: String) -> Response do
  let invite_result = Pool.query(pool, "SELECT i.id, i.org_id, i.email FROM invites i WHERE i.token = $1 AND i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > NOW()", [token])
  case invite_result do
    Err(_) -> HTTP.response(400, json { error: "invalid or expired invite" })
    Ok(invite_rows) -> check_invite_found(pool, invite_rows, user_id)
  end
end

fn handle_accept_with_token(pool, token :: String, request) -> Response do
  let user_result = extract_user_id_inv(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "login or register first" })
    Ok(user_id) -> lookup_invite_for_accept(pool, token, user_id)
  end
end

# POST /api/invites/:token/accept
pub fn accept_invite_handler(pool, request) -> Response do
  let token_opt = Request.param(request, "token")
  case token_opt do
    None -> HTTP.response(400, json { error: "missing token parameter" })
    Some(token) -> handle_accept_with_token(pool, token, request)
  end
end

# ---------------------------------------------------------------------------
# DELETE /api/orgs/:org_id/invites/:invite_id helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn do_revoke_invite(pool, org_id :: String, invite_id :: String) -> Response do
  let revoke_result = Pool.execute(pool, "UPDATE invites SET revoked_at = NOW() WHERE id = $1 AND org_id = $2 AND revoked_at IS NULL", [invite_id, org_id])
  case revoke_result do
    Err(_) -> HTTP.response(500, json { error: "failed to revoke invite" })
    Ok(_) -> HTTP.response(200, json { status: "invite revoked" })
  end
end

fn check_revoke_is_owner(pool, org_id :: String, invite_id :: String, role :: String) -> Response do
  if role != "owner" do
    HTTP.response(403, json { error: "only owners can revoke invites" })
  else
    do_revoke_invite(pool, org_id, invite_id)
  end
end

fn check_revoke_owner(pool, org_id :: String, invite_id :: String, role_rows) -> Response do
  let role_count = List.length(role_rows)
  if role_count == 0 do
    HTTP.response(403, json { error: "not a member of this organization" })
  else
    check_revoke_is_owner(pool, org_id, invite_id, Map.get(List.head(role_rows), "role"))
  end
end

fn verify_owner_for_revoke(pool, org_id :: String, invite_id :: String, user_id :: String) -> Response do
  let role_result = Pool.query(pool, "SELECT role FROM org_memberships WHERE org_id = $1 AND user_id = $2", [org_id, user_id])
  case role_result do
    Err(_) -> HTTP.response(500, json { error: "failed to check role" })
    Ok(role_rows) -> check_revoke_owner(pool, org_id, invite_id, role_rows)
  end
end

fn handle_revoke_params(pool, request, user_id :: String, org_id :: String) -> Response do
  let invite_id_opt = Request.param(request, "invite_id")
  case invite_id_opt do
    None -> HTTP.response(400, json { error: "missing invite_id parameter" })
    Some(invite_id) -> verify_owner_for_revoke(pool, org_id, invite_id, user_id)
  end
end

fn do_revoke_handler(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> handle_revoke_params(pool, request, user_id, org_id)
  end
end

# DELETE /api/orgs/:org_id/invites/:invite_id
pub fn revoke_invite_handler(pool, request) -> Response do
  let user_result = extract_user_id_inv(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_revoke_handler(pool, request, user_id)
  end
end

# ---------------------------------------------------------------------------
# GET /api/orgs/:org_id/invites helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn format_invite_list(rows) -> Response do
  let invites = List.map(rows, fn(row) do
    json { id: Map.get(row, "id"), email: Map.get(row, "email"), expires_at: Map.get(row, "expires_at"), accepted_at: Map.get(row, "accepted_at"), revoked_at: Map.get(row, "revoked_at"), created_at: Map.get(row, "created_at") }
  end)
  HTTP.response(200, json { invites: invites })
end

fn query_invites(pool, org_id :: String) -> Response do
  let invite_result = Pool.query(pool, "SELECT id, email, expires_at, accepted_at, revoked_at, created_at FROM invites WHERE org_id = $1 ORDER BY created_at DESC", [org_id])
  case invite_result do
    Err(_) -> HTTP.response(500, json { error: "failed to list invites" })
    Ok(rows) -> format_invite_list(rows)
  end
end

fn check_list_membership_count(pool, org_id :: String, mem_rows) -> Response do
  let mem_count = List.length(mem_rows)
  if mem_count == 0 do
    HTTP.response(403, json { error: "not a member of this organization" })
  else
    query_invites(pool, org_id)
  end
end

fn check_list_membership(pool, org_id :: String, user_id :: String) -> Response do
  let mem_result = Pool.query(pool, "SELECT role FROM org_memberships WHERE org_id = $1 AND user_id = $2", [org_id, user_id])
  case mem_result do
    Err(_) -> HTTP.response(500, json { error: "failed to check membership" })
    Ok(mem_rows) -> check_list_membership_count(pool, org_id, mem_rows)
  end
end

fn do_list_invites(pool, request, user_id :: String) -> Response do
  let org_id_opt = Request.param(request, "org_id")
  case org_id_opt do
    None -> HTTP.response(400, json { error: "missing org_id parameter" })
    Some(org_id) -> check_list_membership(pool, org_id, user_id)
  end
end

# GET /api/orgs/:org_id/invites
pub fn list_invites_handler(pool, request) -> Response do
  let user_result = extract_user_id_inv(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do_list_invites(pool, request, user_id)
  end
end

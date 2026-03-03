from Src.Mail.Sender import send_email
from Src.Auth.Cookies import extract_user_id
from Src.Storage.Queries import check_membership, get_org, create_invite, get_pending_invite, check_pending_invite_by_email, check_existing_member_by_email, accept_invite, add_member, revoke_invite, list_invites

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

# POST /api/orgs/:org_id/invites
pub fn create_invite_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let raw_body = Request.body(request)
          let parse_result = Json.parse(raw_body)
          case parse_result do
            Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
            Ok(body_json) -> do
              let email = Json.get(body_json, "email")
              let mem_result = check_membership(pool, org_id, user_id)
              case mem_result do
                Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
                Ok(membership) -> do
                  let role = Map.get(membership, "role")
                  if role != "owner" do
                    HTTP.response(403, json { error: "only owners can create invites" })
                  else
                    let org_result = get_org(pool, org_id)
                    case org_result do
                      Err(_) -> HTTP.response(404, json { error: "organization not found" })
                      Ok(org) -> do
                        let org_name = Map.get(org, "name")
                        let is_member = check_existing_member_by_email(pool, org_id, email)
                        case is_member do
                          Err(_) -> HTTP.response(500, json { error: "failed to check membership" })
                          Ok(already_member) -> do
                            if already_member do
                              HTTP.response(409, json { error: "user is already a member" })
                            else
                              let has_pending = check_pending_invite_by_email(pool, org_id, email)
                              case has_pending do
                                Err(_) -> HTTP.response(500, json { error: "failed to check pending invites" })
                                Ok(pending) -> do
                                  if pending do
                                    HTTP.response(409, json { error: "invite already pending" })
                                  else
                                    let token = Crypto.uuid4()
                                    let invite_result = create_invite(pool, org_id, email, token, user_id)
                                    case invite_result do
                                      Err(_) -> HTTP.response(500, json { error: "failed to create invite" })
                                      Ok(_) -> send_invite_email(email, token, org_name)
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

# POST /api/invites/:token/accept
pub fn accept_invite_handler(pool, request) -> Response do
  let token_opt = Request.param(request, "token")
  case token_opt do
    None -> HTTP.response(400, json { error: "missing token parameter" })
    Some(token) -> do
      let user_result = extract_user_id(pool, request)
      case user_result do
        Err(_) -> HTTP.response(401, json { error: "login or register first" })
        Ok(user_id) -> do
          let invite_result = get_pending_invite(pool, token)
          case invite_result do
            Err(_) -> HTTP.response(400, json { error: "invalid or expired invite" })
            Ok(invite) -> do
              let invite_id = Map.get(invite, "id")
              let org_id = Map.get(invite, "org_id")
              let mem_result = add_member(pool, org_id, user_id, "member")
              case mem_result do
                Err(_) -> HTTP.response(500, json { error: "failed to join organization" })
                Ok(_) -> do
                  let _ = accept_invite(pool, invite_id)
                  HTTP.response(200, json { status: "joined", org_id: org_id })
                end
              end
            end
          end
        end
      end
    end
  end
end

# POST /api/orgs/:org_id/invites/:invite_id/revoke
pub fn revoke_invite_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let invite_id_opt = Request.param(request, "invite_id")
          case invite_id_opt do
            None -> HTTP.response(400, json { error: "missing invite_id parameter" })
            Some(invite_id) -> do
              let mem_result = check_membership(pool, org_id, user_id)
              case mem_result do
                Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
                Ok(membership) -> do
                  let role = Map.get(membership, "role")
                  if role != "owner" do
                    HTTP.response(403, json { error: "only owners can revoke invites" })
                  else
                    let revoke_result = revoke_invite(pool, invite_id, org_id)
                    case revoke_result do
                      Err(_) -> HTTP.response(500, json { error: "failed to revoke invite" })
                      Ok(_) -> HTTP.response(200, json { status: "invite revoked" })
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

# GET /api/orgs/:org_id/invites
pub fn list_invites_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let mem_result = check_membership(pool, org_id, user_id)
          case mem_result do
            Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
            Ok(_) -> do
              let invite_result = list_invites(pool, org_id)
              case invite_result do
                Err(_) -> HTTP.response(500, json { error: "failed to list invites" })
                Ok(rows) -> do
                  let invites = List.map(rows, fn(row) do
                    json { id: Map.get(row, "id"), email: Map.get(row, "email"), expires_at: Map.get(row, "expires_at"), accepted_at: Map.get(row, "accepted_at"), revoked_at: Map.get(row, "revoked_at"), created_at: Map.get(row, "created_at") }
                  end)
                  HTTP.response(200, json { invites: invites })
                end
              end
            end
          end
        end
      end
    end
  end
end

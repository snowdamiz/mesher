from Src.Auth.Cookies import extract_user_id
from Src.Storage.Queries import insert_org, get_org, list_user_orgs, add_member, check_membership

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
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let body = Request.body(request)
      let parsed = Json.parse(body)
      case parsed do
        Err(_) -> HTTP.response(400, json { error: "invalid JSON body" })
        Ok(body_json) -> do
          let name = Json.get(body_json, "name")
          let len = String.length(name)
          if len < 1 do
            HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
          else
            if len > 100 do
              HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
            else
              let slug = String.replace(String.lower(name), " ", "-")
              let org_result = insert_org(pool, name, slug)
              case org_result do
                Err(_) -> HTTP.response(500, json { error: "failed to create organization" })
                Ok(org_id) -> do
                  let mem_result = add_member(pool, org_id, user_id, "owner")
                  case mem_result do
                    Err(_) -> HTTP.response(500, json { error: "failed to create organization" })
                    Ok(_) -> HTTP.response(201, json { id: org_id, name: name, slug: slug })
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

# GET /api/orgs
pub fn handle_list_orgs(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let query_result = list_user_orgs(pool, user_id)
      case query_result do
        Err(_) -> HTTP.response(500, json { error: "failed to list organizations" })
        Ok(rows) -> do
          let orgs = List.map(rows, fn(row) do
            json { id: Map.get(row, "id"), name: Map.get(row, "name"), slug: Map.get(row, "slug"), created_at: Map.get(row, "created_at"), role: Map.get(row, "role") }
          end)
          HTTP.response(200, json { organizations: orgs })
        end
      end
    end
  end
end

# GET /api/orgs/:org_id
pub fn handle_get_org(pool, request) -> Response do
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
            Ok(membership) -> do
              let role = Map.get(membership, "role")
              let org_result = get_org(pool, org_id)
              case org_result do
                Err(_) -> HTTP.response(404, json { error: "organization not found" })
                Ok(org) -> HTTP.response(200, json { id: Map.get(org, "id"), name: Map.get(org, "name"), slug: Map.get(org, "slug"), created_at: Map.get(org, "created_at"), role: role })
              end
            end
          end
        end
      end
    end
  end
end

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

from Src.Auth.Cookies import extract_user_id
from Src.Storage.Queries import check_membership, create_project, list_projects, create_api_key, list_api_keys, revoke_api_key

# POST /api/orgs/:org_id/projects
pub fn create_project_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let mem_check = check_membership(pool, org_id, user_id)
          case mem_check do
            Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
            Ok(_) -> do
              let raw_body = Request.body(request)
              let parse_result = Json.parse(raw_body)
              case parse_result do
                Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
                Ok(body_json) -> do
                  let name = Json.get(body_json, "name")
                  let len = String.length(name)
                  if len < 1 do
                    HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
                  else
                    if len > 100 do
                      HTTP.response(400, json { error: "name must be between 1 and 100 characters" })
                    else
                      let project_result = create_project(pool, org_id, name)
                      case project_result do
                        Err(_) -> HTTP.response(500, json { error: "failed to create project" })
                        Ok(project_id) -> HTTP.response(201, json { id: project_id, name: name })
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

# GET /api/orgs/:org_id/projects
pub fn list_projects_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let mem_check = check_membership(pool, org_id, user_id)
          case mem_check do
            Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
            Ok(_) -> do
              let query_result = list_projects(pool, org_id)
              case query_result do
                Err(_) -> HTTP.response(500, json { error: "failed to list projects" })
                Ok(rows) -> do
                  let projects = List.map(rows, fn(row) do
                    json { id: Map.get(row, "id"), name: Map.get(row, "name"), created_at: Map.get(row, "created_at") }
                  end)
                  HTTP.response(200, json { projects: projects })
                end
              end
            end
          end
        end
      end
    end
  end
end

# POST /api/orgs/:org_id/projects/:project_id/api-keys
pub fn create_api_key_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let mem_check = check_membership(pool, org_id, user_id)
          case mem_check do
            Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
            Ok(_) -> do
              let project_id_opt = Request.param(request, "project_id")
              case project_id_opt do
                None -> HTTP.response(400, json { error: "missing project_id parameter" })
                Some(project_id) -> do
                  let raw_body = Request.body(request)
                  let label = case Json.parse(raw_body) do
                    Err(_) -> ""
                    Ok(body_json) -> Json.get(body_json, "label")
                  end
                  let raw_key = Crypto.uuid4()
                  let key_prefix = String.slice(raw_key, 0, 8)
                  let key_hash = Crypto.sha256(raw_key)
                  let insert_result = create_api_key(pool, project_id, key_hash, key_prefix, label)
                  let host = Env.get("APP_URL", "http://localhost:8080")
                  let dsn = host <> "/api/" <> project_id <> "/"
                  case insert_result do
                    Err(_) -> HTTP.response(500, json { error: "failed to create API key" })
                    Ok(key_id) -> HTTP.response(201, json { id: key_id, key: raw_key, prefix: key_prefix, dsn: dsn })
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

# GET /api/orgs/:org_id/projects/:project_id/api-keys
pub fn list_api_keys_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let mem_check = check_membership(pool, org_id, user_id)
          case mem_check do
            Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
            Ok(_) -> do
              let project_id_opt = Request.param(request, "project_id")
              case project_id_opt do
                None -> HTTP.response(400, json { error: "missing project_id parameter" })
                Some(project_id) -> do
                  let query_result = list_api_keys(pool, project_id)
                  case query_result do
                    Err(_) -> HTTP.response(500, json { error: "failed to list API keys" })
                    Ok(rows) -> do
                      let keys = List.map(rows, fn(row) do
                        json { id: Map.get(row, "id"), project_id: Map.get(row, "project_id"), key_prefix: Map.get(row, "key_prefix"), label: Map.get(row, "label"), created_at: Map.get(row, "created_at"), revoked_at: Map.get(row, "revoked_at") }
                      end)
                      HTTP.response(200, json { api_keys: keys })
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

# POST /api/orgs/:org_id/api-keys/:key_id/revoke
pub fn revoke_api_key_handler(pool, request) -> Response do
  let user_result = extract_user_id(pool, request)
  case user_result do
    Err(_) -> HTTP.response(401, json { error: "unauthorized" })
    Ok(user_id) -> do
      let org_id_opt = Request.param(request, "org_id")
      case org_id_opt do
        None -> HTTP.response(400, json { error: "missing org_id parameter" })
        Some(org_id) -> do
          let mem_check = check_membership(pool, org_id, user_id)
          case mem_check do
            Err(_) -> HTTP.response(403, json { error: "not a member of this organization" })
            Ok(_) -> do
              let key_id_opt = Request.param(request, "key_id")
              case key_id_opt do
                None -> HTTP.response(400, json { error: "missing key_id parameter" })
                Some(key_id) -> do
                  let revoke_result = revoke_api_key(pool, key_id)
                  case revoke_result do
                    Err(_) -> HTTP.response(500, json { error: "failed to revoke API key" })
                    Ok(_) -> HTTP.response(200, json { status: "API key revoked" })
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

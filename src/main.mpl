# Mesher application entry point
# Starts the HTTP server with a connection pool, health endpoint,
# authentication routes, org management, and feature endpoints.
#
# Cross-module imports use `from Module import func` for inter-file access.
# All handler functions are defined in their respective module files with `pub fn`.
#
# Functions MUST be defined before use (no forward references).

from Auth.Session import handle_login, handle_logout
from Auth.Reset import request_reset_handler, confirm_reset_handler
from Auth.Oauth import google_oauth_start, google_oauth_callback
from Org.Handlers import handle_create_org, handle_list_orgs, handle_get_org
from Org.Invites import create_invite_handler, accept_invite_handler, list_invites_handler, revoke_invite_handler
from Project.Projects import create_project_handler, list_projects_handler, create_api_key_handler, list_api_keys_handler, revoke_api_key_handler

fn start_server(pool, port :: Int) do
  let router = HTTP.router()
    |> HTTP.on_get("/health", fn(request) do
      HTTP.response(200, json { status: "ok" })
    end)
    # Public auth routes (no session required)
    |> HTTP.on_post("/api/login", fn(request) do
      handle_login(pool, request)
    end)
    |> HTTP.on_post("/api/logout", fn(request) do
      handle_logout(pool, request)
    end)
    |> HTTP.on_post("/api/auth/reset-password", fn(request) do
      request_reset_handler(pool, request)
    end)
    |> HTTP.on_post("/api/auth/reset-password/confirm", fn(request) do
      confirm_reset_handler(pool, request)
    end)
    |> HTTP.on_get("/api/auth/oauth/google", fn(request) do
      google_oauth_start(pool, request)
    end)
    |> HTTP.on_get("/api/auth/oauth/google/callback", fn(request) do
      google_oauth_callback(pool, request)
    end)
    # Semi-public route (invite accept - handles auth check internally)
    |> HTTP.on_post("/api/invites/:token/accept", fn(request) do
      accept_invite_handler(pool, request)
    end)
    # Authenticated routes (org management)
    |> HTTP.on_post("/api/orgs", fn(request) do
      handle_create_org(pool, request)
    end)
    |> HTTP.on_get("/api/orgs", fn(request) do
      handle_list_orgs(pool, request)
    end)
    |> HTTP.on_get("/api/orgs/:org_id", fn(request) do
      handle_get_org(pool, request)
    end)
    # Invite management (authenticated, org-scoped)
    |> HTTP.on_post("/api/orgs/:org_id/invites", fn(request) do
      create_invite_handler(pool, request)
    end)
    |> HTTP.on_get("/api/orgs/:org_id/invites", fn(request) do
      list_invites_handler(pool, request)
    end)
    |> HTTP.on_post("/api/orgs/:org_id/invites/:invite_id/revoke", fn(request) do
      revoke_invite_handler(pool, request)
    end)
    # Project management (authenticated, org-scoped)
    |> HTTP.on_post("/api/orgs/:org_id/projects", fn(request) do
      create_project_handler(pool, request)
    end)
    |> HTTP.on_get("/api/orgs/:org_id/projects", fn(request) do
      list_projects_handler(pool, request)
    end)
    # API key management (authenticated, org-scoped)
    |> HTTP.on_post("/api/orgs/:org_id/projects/:project_id/api-keys", fn(request) do
      create_api_key_handler(pool, request)
    end)
    |> HTTP.on_get("/api/orgs/:org_id/projects/:project_id/api-keys", fn(request) do
      list_api_keys_handler(pool, request)
    end)
    |> HTTP.on_post("/api/orgs/:org_id/api-keys/:key_id/revoke", fn(request) do
      revoke_api_key_handler(pool, request)
    end)

  HTTP.serve(router, port)
end

fn main() do
  let db_url = Env.get("DATABASE_URL", "postgres://mesh:mesh@localhost:5432/mesher")
  let port = Env.get_int("HTTP_PORT", 8080)
  println("[Mesher] Connecting to PostgreSQL...")
  let pool_result = Pool.open(db_url, 2, 10, 5000)
  case pool_result do
    Ok(pool) -> start_server(pool, port)
    Err(_) -> println("[Mesher] Failed to connect to PostgreSQL")
  end
end

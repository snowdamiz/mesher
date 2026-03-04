# Mesher application entry point
# Starts the HTTP server with a connection pool, health endpoint,
# authentication routes, org management, and feature endpoints.

from Src.Auth.Session import handle_login, handle_logout
from Src.Auth.Reset import request_reset_handler, confirm_reset_handler
from Src.Auth.Oauth import google_oauth_start, google_oauth_callback
from Src.Org.Handlers import handle_create_org, handle_list_orgs, handle_get_org
from Src.Org.Invites import create_invite_handler, accept_invite_handler, list_invites_handler, revoke_invite_handler
from Src.Project.Projects import create_project_handler, list_projects_handler, create_api_key_handler, list_api_keys_handler, revoke_api_key_handler
from Src.Ingest.Envelope import handle_sentry_envelope
from Src.Ingest.Otlp import handle_otlp_logs, handle_otlp_traces, handle_otlp_metrics
from Src.Ingest.Generic import handle_generic_event
from Src.Ingest.Health import handle_health_ingest

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
    # Ingestion endpoints (API key auth, not session auth)
    |> HTTP.on_post("/api/:project_id/envelope/", fn(request) do
      handle_sentry_envelope(pool, request)
    end)
    # OTLP/HTTP ingestion endpoints (API key auth via Bearer token)
    # Routes on same port (8080) with path-based routing.
    # Production deployments can use reverse proxy to map port 4318 to these paths.
    |> HTTP.on_post("/v1/logs", fn(request) do
      handle_otlp_logs(pool, request)
    end)
    |> HTTP.on_post("/v1/traces", fn(request) do
      handle_otlp_traces(pool, request)
    end)
    |> HTTP.on_post("/v1/metrics", fn(request) do
      handle_otlp_metrics(pool, request)
    end)
    # Generic JSON API (API key auth via Bearer token)
    |> HTTP.on_post("/api/:project_id/events", fn(request) do
      handle_generic_event(pool, request)
    end)
    # Ingestion health endpoint
    |> HTTP.on_get("/health/ingest", fn(request) do
      handle_health_ingest(pool, request)
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

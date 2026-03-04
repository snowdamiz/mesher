# Google OAuth authorization code flow (AUTH-05, SaaS only)
#
# Implements Google OAuth 2.0 authorization code flow:
#   GET /api/auth/oauth/google          - Redirect to Google authorization
#   GET /api/auth/oauth/google/callback  - Handle callback, create/find user, session
#
# SaaS-only: returns 403 if MESHER_TIER != "saas".
# First sign-in auto-creates account (no separate registration step).
# All data access goes through centralized storage/queries.mpl ORM functions.
# No inline SQL in this module.

from Src.Auth.Guards import require_query, guard_error
from Src.Storage.Queries import store_oauth_state, validate_oauth_state, delete_oauth_state, upsert_oauth_user, create_session

fn build_google_auth_url(state :: String) -> String do
  let client_id = Env.get("GOOGLE_CLIENT_ID", "")
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let redirect_uri = app_url <> "/api/auth/oauth/google/callback"
  "https://accounts.google.com/o/oauth2/v2/auth?client_id=" <> client_id <> "&redirect_uri=" <> redirect_uri <> "&response_type=code&scope=openid%20email&state=" <> state <> "&access_type=online"
end

fn saas_only_error() -> Response do
  HTTP.response(403, json { error: "Google OAuth is only available on SaaS tier" })
end

fn create_oauth_session_response(pool, user_id :: String) -> Response do
  let session_result = create_session(pool, user_id)
  case session_result do
    Err(_) -> HTTP.response(500, json { error: "session creation failed" })
    Ok(token) -> HTTP.response_with_headers(302, "", %{"Set-Cookie" => "mesher_session=" <> token <> "; HttpOnly; Path=/; SameSite=Lax; Max-Age=86400", "Location" => "/"})
  end
end

# Stub: In production, exchange the authorization code for tokens via POST
# to https://oauth2.googleapis.com/token, then fetch user info from
# https://www.googleapis.com/oauth2/v2/userinfo.
# Mesh HTTP client API needs verification before implementing real calls.
fn exchange_code_stub(pool, code :: String) -> Response do
  let _ = println("[OAUTH] Received authorization code: " <> code)
  let _ = println("[OAUTH] Token exchange requires Mesh HTTP client (unverified API)")
  HTTP.response(501, json { error: "OAuth token exchange not yet implemented - Mesh HTTP client API needs verification", code: code })
end

# GET /api/auth/oauth/google
pub fn google_oauth_start(pool, request) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let cond = tier != "saas"
  if cond do
    saas_only_error()
  else
    let state = Crypto.uuid4()
    let store_result = store_oauth_state(pool, state)
    case store_result do
      Err(_) -> HTTP.response(500, json { error: "failed to store OAuth state" })
      Ok(_) -> do
        let auth_url = build_google_auth_url(state)
        HTTP.response_with_headers(302, "", %{"Location" => auth_url})
      end
    end
  end
end

fn extract_oauth_params(request) -> Map<String, String>!String do
  let code = require_query(request, "code")?
  let state = require_query(request, "state")?
  Ok(%{"code" => code, "state" => state})
end

fn do_oauth_callback(pool, request) -> Response!String do
  let params = extract_oauth_params(request)?
  let code = Map.get(params, "code")
  let state = Map.get(params, "state")
  let cond = validate_oauth_state(pool, state)?
  if cond do
    let _ = delete_oauth_state(pool, state)
    Ok(exchange_code_stub(pool, code))
  else
    Err("invalid or expired OAuth state")
  end
end

# GET /api/auth/oauth/google/callback
pub fn google_oauth_callback(pool, request) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let cond = tier != "saas"
  if cond do
    saas_only_error()
  else
    case do_oauth_callback(pool, request) do
      Err(e) -> guard_error(e)
      Ok(r) -> r
    end
  end
end

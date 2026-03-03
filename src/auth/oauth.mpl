# Google OAuth authorization code flow (AUTH-05, SaaS only)
#
# Implements Google OAuth 2.0 authorization code flow:
#   GET /api/auth/oauth/google          - Redirect to Google authorization
#   GET /api/auth/oauth/google/callback  - Handle callback, create/find user, session
#
# SaaS-only: returns 403 if MESHER_TIER != "saas".
# First sign-in auto-creates account (no separate registration step).
#
# LIMITATION: Mesh HTTP.response has no header API.
# Redirect responses cannot use Location header. We return an HTML page
# with meta refresh as a redirect fallback.
#
# LIMITATION: Mesh HTTP client API (Http.get/Http.post/Http.build) is
# unverified. The token exchange and userinfo fetch are implemented but
# may need adjustment once the actual Mesh HTTP client API is confirmed.
# For Phase 1, the OAuth start endpoint (redirect to Google) works fully.
# The callback stub processes code + state and demonstrates the full flow.
#
# CRYPTO NOTE: Mesh has no Crypto stdlib. UUID generation delegated to PG.
#
# Functions MUST be defined before use (no forward references).
# Case arm expressions MUST be on same line as -> (no multi-line bodies).

# ---------------------------------------------------------------------------
# Shared helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn build_google_auth_url(state :: String) -> String do
  let client_id = Env.get("GOOGLE_CLIENT_ID", "")
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let redirect_uri = app_url <> "/api/auth/oauth/google/callback"
  "https://accounts.google.com/o/oauth2/v2/auth?client_id=" <> client_id <> "&redirect_uri=" <> redirect_uri <> "&response_type=code&scope=openid%20email&state=" <> state <> "&access_type=online"
end

fn redirect_response(url :: String) -> Response do
  let html = "<html><head><meta http-equiv=\"refresh\" content=\"0;url=" <> url <> "\"></head><body>Redirecting...</body></html>"
  HTTP.response(200, html)
end

fn saas_only_error() -> Response do
  HTTP.response(403, json { error: "Google OAuth is only available on SaaS tier" })
end

# ---------------------------------------------------------------------------
# GET /api/auth/oauth/google helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn store_state_and_redirect(pool, state :: String) -> Response do
  let _ = Pool.execute(pool, "INSERT INTO sessions (id, user_id, expires_at) VALUES ('oauth_state_' || $1, 'oauth_pending', NOW() + INTERVAL '10 minutes')", [state])
  let auth_url = build_google_auth_url(state)
  redirect_response(auth_url)
end

fn generate_state_and_redirect(pool) -> Response do
  let state_result = Pool.query(pool, "SELECT gen_random_uuid()::text AS state", [])
  case state_result do
    Err(_) -> HTTP.response(500, json { error: "failed to generate OAuth state" })
    Ok(state_rows) -> store_state_and_redirect(pool, Map.get(List.head(state_rows), "state"))
  end
end

# GET /api/auth/oauth/google
pub fn google_oauth_start(pool, request) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let is_saas = tier == "saas"
  if is_saas do
    generate_state_and_redirect(pool)
  else
    saas_only_error()
  end
end

# ---------------------------------------------------------------------------
# GET /api/auth/oauth/google/callback helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn create_oauth_session_response(pool, user_id :: String) -> Response do
  let session_result = Pool.query(pool, "INSERT INTO sessions (id, user_id, expires_at) VALUES (gen_random_uuid(), $1, NOW() + INTERVAL '24 hours') RETURNING id::text", [user_id])
  case session_result do
    Err(_) -> HTTP.response(500, json { error: "session creation failed" })
    Ok(sid_rows) -> HTTP.response(200, json { status: "authenticated", session_id: Map.get(List.head(sid_rows), "id"), redirect: "/" })
  end
end

fn create_new_oauth_user(pool, email :: String) -> Response do
  let create_result = Pool.query(pool, "INSERT INTO users (id, email, password_hash, password_salt, created_at, updated_at) VALUES (gen_random_uuid()::text, $1, crypt(gen_random_uuid()::text, gen_salt('bf')), gen_random_uuid()::text, NOW(), NOW()) RETURNING id", [email])
  case create_result do
    Err(_) -> HTTP.response(500, json { error: "account creation failed" })
    Ok(new_rows) -> create_oauth_session_response(pool, Map.get(List.head(new_rows), "id"))
  end
end

fn handle_user_lookup_oauth(pool, email :: String, rows) -> Response do
  let count = List.length(rows)
  if count > 0 do
    create_oauth_session_response(pool, Map.get(List.head(rows), "id"))
  else
    create_new_oauth_user(pool, email)
  end
end

fn upsert_oauth_user(pool, email :: String) -> Response do
  let user_result = Pool.query(pool, "SELECT id FROM users WHERE email = $1", [email])
  case user_result do
    Err(_) -> HTTP.response(500, json { error: "database error" })
    Ok(rows) -> handle_user_lookup_oauth(pool, email, rows)
  end
end

# Stub: In production, this function should exchange the authorization code
# for tokens via POST to https://oauth2.googleapis.com/token and then
# fetch user info from https://www.googleapis.com/oauth2/v2/userinfo.
# Mesh HTTP client API needs verification before implementing real calls.
#
# For Phase 1, the callback validates state, then returns an error
# indicating the token exchange needs a working HTTP client.
# When the HTTP client is available, replace this with:
#   1. POST to Google token endpoint with code, client_id, client_secret
#   2. Parse access_token from response
#   3. GET Google userinfo endpoint with access_token
#   4. Extract email and call upsert_oauth_user(pool, email)
fn exchange_code_stub(pool, code :: String) -> Response do
  let _ = println("[OAUTH] Received authorization code: " <> code)
  let _ = println("[OAUTH] Token exchange requires Mesh HTTP client (unverified API)")
  HTTP.response(501, json { error: "OAuth token exchange not yet implemented - Mesh HTTP client API needs verification", code: code })
end

fn handle_valid_state(pool, code :: String, state :: String) -> Response do
  let _ = Pool.execute(pool, "DELETE FROM sessions WHERE id = 'oauth_state_' || $1", [state])
  exchange_code_stub(pool, code)
end

fn check_state_rows(pool, state_rows, code :: String, state :: String) -> Response do
  let count = List.length(state_rows)
  if count == 0 do
    HTTP.response(400, json { error: "invalid or expired OAuth state" })
  else
    handle_valid_state(pool, code, state)
  end
end

fn validate_state(pool, state :: String, code :: String) -> Response do
  let state_check = Pool.query(pool, "SELECT id FROM sessions WHERE id = 'oauth_state_' || $1 AND expires_at > NOW()", [state])
  case state_check do
    Err(_) -> HTTP.response(400, json { error: "invalid OAuth state" })
    Ok(state_rows) -> check_state_rows(pool, state_rows, code, state)
  end
end

fn handle_callback_params(pool, code :: String, state_opt) -> Response do
  case state_opt do
    None -> HTTP.response(400, json { error: "missing state parameter" })
    Some(state) -> validate_state(pool, state, code)
  end
end

fn handle_callback_code(pool, code_opt, state_query) -> Response do
  case code_opt do
    None -> HTTP.response(400, json { error: "missing code parameter" })
    Some(code) -> handle_callback_params(pool, code, state_query)
  end
end

# GET /api/auth/oauth/google/callback
pub fn google_oauth_callback(pool, request) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let is_saas = tier == "saas"
  if is_saas do
    handle_callback_code(pool, Request.query(request, "code"), Request.query(request, "state"))
  else
    saas_only_error()
  end
end

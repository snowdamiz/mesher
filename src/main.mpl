# Mesher application entry point
# Starts the HTTP server with a connection pool, health endpoint,
# authentication routes, org management, and feature endpoints.
#
# Cross-module imports use `import X.Y` with `pub fn` for inter-file access.
# (Established pattern from Plan 04: import Org.Handlers / import Org.Schema)
#
# Functions MUST be defined before use (no forward references).

import Auth.Reset
import Auth.Oauth
import Org.Handlers

# Cookie parsing helpers.
fn extract_session_value(raw_val :: String) -> String do
  let has_semi = String.contains(raw_val, ";")
  if has_semi do
    let parts = String.split(raw_val, ";")
    let first = List.head(parts)
    String.trim(first)
  else
    String.trim(raw_val)
  end
end

fn parse_session_cookie(cookie_str :: String) -> String do
  let has_key = String.contains(cookie_str, "mesher_session=")
  if has_key do
    let parts = String.split(cookie_str, "mesher_session=")
    let raw_value = List.last(parts)
    extract_session_value(raw_value)
  else
    ""
  end
end

# Verify password and create session, return response.
fn handle_verified_rows(pool, rows) -> Response do
  let count = List.length(rows)
  if count > 0 do
    let user_row = List.head(rows)
    let email = Map.get(user_row, "email")
    let user_id = Map.get(user_row, "id")
    let _ = Pool.execute(pool, "DELETE FROM sessions WHERE expires_at < NOW()", [])
    let insert_result = Pool.query(pool,
      "INSERT INTO sessions (id, user_id, expires_at) VALUES (gen_random_uuid(), $1, NOW() + INTERVAL '24 hours') RETURNING id::text",
      [user_id])
    case insert_result do
      Ok(sid_rows) -> HTTP.response(200, json { email: email, session_id: Map.get(List.head(sid_rows), "id") })
      Err(_e) -> HTTP.response(500, json { error: "session creation failed" })
    end
  else
    HTTP.response(401, json { error: "invalid email or password" })
  end
end

fn verify_and_respond(pool, email, password) -> Response do
  let verify_result = Pool.query(pool,
    "SELECT id, email FROM users WHERE email = $1 AND password_hash = crypt($2, password_hash)",
    [email, password])
  case verify_result do
    Ok(rows) -> handle_verified_rows(pool, rows)
    Err(_e) -> HTTP.response(500, json { error: "database error" })
  end
end

fn do_login(pool, body) -> Response do
  let email = Json.get(body, "email")
  let password = Json.get(body, "password")
  verify_and_respond(pool, email, password)
end

fn handle_login(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Ok(body) -> do_login(pool, body)
    Err(_e) -> HTTP.response(400, json { error: "invalid JSON" })
  end
end

fn do_logout(pool, cookie_str) -> Response do
  let sid = parse_session_cookie(cookie_str)
  if sid != "" do
    let _ = Pool.execute(pool, "DELETE FROM sessions WHERE id = $1", [sid])
    HTTP.response(200, json { status: "logged out" })
  else
    HTTP.response(200, json { status: "logged out" })
  end
end

fn handle_logout(pool, request) -> Response do
  let cookie = Request.header(request, "cookie")
  case cookie do
    Some(cookie_str) -> do_logout(pool, cookie_str)
    None -> HTTP.response(200, json { status: "logged out" })
  end
end

fn main() do
  let db_url = Env.get("DATABASE_URL", "postgres://mesh:mesh@localhost:5432/mesher")
  let port = Env.get_int("HTTP_PORT", 8080)
  let pool = Pool.open(db_url, 2, 10, 5000)?

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
      Reset.request_reset_handler(pool, request)
    end)
    |> HTTP.on_post("/api/auth/reset-password/confirm", fn(request) do
      Reset.confirm_reset_handler(pool, request)
    end)
    |> HTTP.on_get("/api/auth/oauth/google", fn(request) do
      Oauth.google_oauth_start(pool, request)
    end)
    |> HTTP.on_get("/api/auth/oauth/google/callback", fn(request) do
      Oauth.google_oauth_callback(pool, request)
    end)
    # Authenticated routes (org management)
    |> HTTP.on_post("/api/orgs", fn(request) do
      Handlers.handle_create_org(pool, request)
    end)
    |> HTTP.on_get("/api/orgs", fn(request) do
      Handlers.handle_list_orgs(pool, request)
    end)
    |> HTTP.on_get("/api/orgs/:org_id", fn(request) do
      Handlers.handle_get_org(pool, request)
    end)

  HTTP.serve(router, port)
end

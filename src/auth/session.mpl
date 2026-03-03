# Auth: PG-backed session store, auth middleware, and tier gate
# (AUTH-01, AUTH-02, AUTH-03)
#
# Sessions are stored in the public.sessions table with a 24-hour expiry.
# UUID generation uses Mesh's native Crypto.uuid4().
# bcrypt password verification is delegated to PostgreSQL pgcrypto crypt()
# because bcrypt is not available in Mesh stdlib (sha256/sha512/hmac are).
#
# KNOWN LIMITATION: Mesh HTTP stdlib has no response header API.
# HTTP.set_header, HTTP.header, HTTP.with_header, HTTP.add_header,
# Response.set_header do not exist. HTTP.response only takes (status, body).
# Set-Cookie headers cannot be set from user code until Mesh adds this API.
# Session cookie delivery will require a Mesh runtime enhancement.
#
# Functions MUST be defined before use (no forward references in Mesh).

# Extract session value from raw cookie substring.
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

# Parse mesher_session cookie value from cookie header string.
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

fn respond_unauthorized() -> Response do
  HTTP.response(401, json { error: "unauthorized" })
end

fn respond_saas_only() -> Response do
  HTTP.response(403, json { error: "SaaS only" })
end

# Remove all expired sessions from the database.
fn cleanup_expired(pool) do
  Pool.execute(pool, "DELETE FROM sessions WHERE expires_at < NOW()", [])
end

# Destroy a single session by ID.
fn destroy_session(pool, session_id :: String) do
  Pool.execute(pool, "DELETE FROM sessions WHERE id = $1", [session_id])
end

# Destroy all sessions for a user.
fn destroy_user_sessions(pool, user_id :: String) do
  Pool.execute(pool, "DELETE FROM sessions WHERE user_id = $1", [user_id])
end

# Validate session rows from query.
fn handle_validated_rows(rows, request, next) -> Response do
  let count = List.length(rows)
  if count > 0 do
    next(request)
  else
    respond_unauthorized()
  end
end

# Validate session and continue request chain.
fn handle_validate_ok(pool, sid :: String, request, next) -> Response do
  let query_result = Pool.query(pool,
    "SELECT s.user_id FROM sessions s WHERE s.id = $1 AND s.expires_at > NOW()",
    [sid])
  case query_result do
    Ok(rows) -> handle_validated_rows(rows, request, next)
    Err(_e) -> respond_unauthorized()
  end
end

fn check_session(pool, request, next, cookie_str) -> Response do
  let sid = parse_session_cookie(cookie_str)
  if sid == "" do
    respond_unauthorized()
  else
    handle_validate_ok(pool, sid, request, next)
  end
end

# HTTP middleware: validate mesher_session cookie on every request.
fn auth_middleware(pool) do
  fn(request, next) do
    let cookie = Request.header(request, "cookie")
    case cookie do
      Some(cookie_str) -> check_session(pool, request, next, cookie_str)
      None -> respond_unauthorized()
    end
  end
end

# Tier gate: block SaaS-only routes when MESHER_TIER != "saas".
fn tier_gate(request, next) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let path = Request.path(request)
  let is_saas_route = String.starts_with(path, "/api/v1/ai/")
  let is_blocked = is_saas_route && tier != "saas"
  if is_blocked do
    respond_saas_only()
  else
    next(request)
  end
end

# Handle verified password rows.
fn handle_verified_rows(pool, rows) -> Response do
  let count = List.length(rows)
  if count > 0 do
    let user_row = List.head(rows)
    let email = Map.get(user_row, "email")
    let user_id = Map.get(user_row, "id")
    let _ = cleanup_expired(pool)
    let session_id = Crypto.uuid4()
    let insert_result = Pool.execute(pool,
      "INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, NOW() + INTERVAL '24 hours')",
      [session_id, user_id])
    case insert_result do
      Ok(_) -> HTTP.response(200, json { email: email, session_id: session_id })
      Err(_e) -> HTTP.response(500, json { error: "session creation failed" })
    end
  else
    HTTP.response(401, json { error: "invalid email or password" })
  end
end

# Verify password and handle result.
fn verify_and_respond(pool, email, password) -> Response do
  let verify_result = Pool.query(pool,
    "SELECT id, email FROM users WHERE email = $1 AND password_hash = crypt($2, password_hash)",
    [email, password])
  case verify_result do
    Ok(rows) -> handle_verified_rows(pool, rows)
    Err(_e) -> HTTP.response(500, json { error: "database error" })
  end
end

# Handle parsed login body.
fn do_login(pool, body) -> Response do
  let email = Json.get(body, "email")
  let password = Json.get(body, "password")
  verify_and_respond(pool, email, password)
end

# POST /api/login handler.
fn handle_login(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Ok(body) -> do_login(pool, body)
    Err(_e) -> HTTP.response(400, json { error: "invalid JSON" })
  end
end

# Handle logout with valid cookie string.
fn do_logout(pool, cookie_str) -> Response do
  let sid = parse_session_cookie(cookie_str)
  if sid != "" do
    let _ = destroy_session(pool, sid)
    HTTP.response(200, json { status: "logged out" })
  else
    HTTP.response(200, json { status: "logged out" })
  end
end

# POST /api/logout handler.
fn handle_logout(pool, request) -> Response do
  let cookie = Request.header(request, "cookie")
  case cookie do
    Some(cookie_str) -> do_logout(pool, cookie_str)
    None -> HTTP.response(200, json { status: "logged out" })
  end
end

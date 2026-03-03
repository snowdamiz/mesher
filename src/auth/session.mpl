# Auth: PG-backed session store, auth middleware, and tier gate
# (AUTH-01, AUTH-02, AUTH-03)
#
# Sessions are stored in the public.sessions table with a 24-hour expiry.
# Using PostgreSQL sessions instead of Valkey since Mesh may lack a Valkey
# client (see research Open Question #1). Periodic cleanup removes expired
# sessions opportunistically on login.
#
# auth_middleware: Validates the mesher_session cookie on every request.
# tier_gate: Blocks SaaS-only routes when running in OSS mode.
#
# All session functions operate against the public schema (not tenant-scoped).

# ---------------------------------------------------------------------------
# Session store functions
# ---------------------------------------------------------------------------

# Create a new session for a user.
# Returns the session ID (UUID) which becomes the cookie value.
# The session expires 24 hours from creation.
fn create_session(pool, user_id :: String) -> String!String do
  let session_id = Crypto.uuid4()
  let _ = Pool.execute(pool,
    "INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, NOW() + INTERVAL '24 hours')",
    [session_id, user_id])?
  Ok(session_id)
end

# Validate a session by ID.
# Returns Ok(Some(row)) if valid, Ok(None) if expired/missing.
# Joins with users table to return user context in a single query.
fn validate_session(pool, session_id :: String) do
  let rows = Pool.query(pool,
    "SELECT s.id, s.user_id, u.email FROM sessions s JOIN users u ON s.user_id = u.id WHERE s.id = $1 AND s.expires_at > NOW()",
    [session_id])?
  let count = List.length(rows)
  if count > 0 do
    Ok(Some(List.head(rows)))
  else
    Ok(None)
  end
end

# Destroy a single session by ID.
# Used for logout -- immediately invalidates the session.
fn destroy_session(pool, session_id :: String) -> Int!String do
  Pool.execute(pool, "DELETE FROM sessions WHERE id = $1", [session_id])
end

# Destroy all sessions for a user.
# Used for password reset (invalidate all sessions) and logout-everywhere.
fn destroy_user_sessions(pool, user_id :: String) -> Int!String do
  Pool.execute(pool, "DELETE FROM sessions WHERE user_id = $1", [user_id])
end

# Remove all expired sessions from the database.
# Called opportunistically during login to keep the sessions table clean.
fn cleanup_expired(pool) -> Int!String do
  Pool.execute(pool, "DELETE FROM sessions WHERE expires_at < NOW()", [])
end

# ---------------------------------------------------------------------------
# Cookie parsing helpers
# ---------------------------------------------------------------------------

# Extract the session ID portion from the raw cookie value substring.
# Input is everything after "mesher_session=" up to a semicolon or end of string.
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

# Parse the mesher_session cookie value from a cookie header string.
# Cookie format: "key1=val1; key2=val2; ..."
# Returns the session ID string or empty string if not found.
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

# ---------------------------------------------------------------------------
# Auth middleware
# ---------------------------------------------------------------------------

fn respond_unauthorized() do
  HTTP.response(401, json { error: "unauthorized" })
end

fn respond_saas_only() do
  HTTP.response(403, json { error: "SaaS only" })
end

# Handle the session validation result (Some/None).
fn handle_session_result(session, request, next) do
  case session do
    Some(_user) -> next(request)
    None -> respond_unauthorized()
  end
end

# Validate session and continue the middleware chain if valid.
fn validate_and_continue(pool, request, next, sid) do
  let result = validate_session(pool, sid)
  case result do
    Ok(session) -> handle_session_result(session, request, next)
    Err(_e) -> respond_unauthorized()
  end
end

# Check session cookie from the cookie string and validate.
fn check_session(pool, request, next, cookie_str) do
  let sid = parse_session_cookie(cookie_str)
  if sid == "" do
    respond_unauthorized()
  else
    validate_and_continue(pool, request, next, sid)
  end
end

# HTTP middleware that validates the session cookie.
#
# Extracts mesher_session from the Cookie header, validates against the
# sessions table via validate_session, and returns 401 if invalid.
#
# If valid, calls next(request) to continue the middleware chain.
fn auth_middleware(pool) do
  fn(request, next) do
    let cookie = Request.header(request, "cookie")
    case cookie do
      Some(cookie_str) -> check_session(pool, request, next, cookie_str)
      None -> respond_unauthorized()
    end
  end
end

# ---------------------------------------------------------------------------
# Tier gate middleware
# ---------------------------------------------------------------------------

# Checks MESHER_TIER env var (via Config.tier()). If tier is "oss" and the
# request path starts with "/api/v1/ai/", returns 403 "SaaS only".
# Otherwise, passes the request through to the next handler.
fn tier_gate(request, next) do
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

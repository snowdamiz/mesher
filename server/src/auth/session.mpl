# Auth: Session store, auth middleware, and tier gate
# (AUTH-01, AUTH-02, AUTH-03)
#
# Sessions are stored in the public.sessions table with a 24-hour expiry.
# All data access goes through centralized storage/queries.mpl ORM functions.
# No inline SQL in this module.

from Src.Storage.Queries import authenticate_user, create_session, delete_session, cleanup_expired_sessions, validate_session

# Extract session value from raw cookie substring.
fn extract_session_value(raw_val :: String) -> String do
  if String.contains(raw_val, ";") do
    let parts = String.split(raw_val, ";")
    let first = List.head(parts)
    String.trim(first)
  else
    String.trim(raw_val)
  end
end

# Parse mesher_session cookie value from cookie header string.
fn parse_session_cookie(cookie_str :: String) -> String do
  if String.contains(cookie_str, "mesher_session=") do
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

# POST /api/login
pub fn handle_login(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body) -> do
      let email = Json.get(body, "email")
      let password = Json.get(body, "password")
      let auth_result = authenticate_user(pool, email, password)
      case auth_result do
        Err(_) -> HTTP.response(401, json { error: "invalid email or password" })
        Ok(user_row) -> do
          let user_id = Map.get(user_row, "id")
          let user_email = Map.get(user_row, "email")
          let _ = cleanup_expired_sessions(pool)
          let session_result = create_session(pool, user_id)
          case session_result do
            Err(_) -> HTTP.response(500, json { error: "session creation failed" })
            Ok(token) -> HTTP.response_with_headers(200, json { email: user_email }, %{"Set-Cookie" => "mesher_session=" <> token <> "; HttpOnly; Path=/; SameSite=Lax; Max-Age=86400"})
          end
        end
      end
    end
  end
end

# POST /api/logout
pub fn handle_logout(pool, request) -> Response do
  let cookie = Request.header(request, "cookie")
  let clear_cookie = %{"Set-Cookie" => "mesher_session=; HttpOnly; Path=/; Max-Age=0"}
  case cookie do
    None -> HTTP.response_with_headers(200, json { status: "logged out" }, clear_cookie)
    Some(cookie_str) -> do
      let token = parse_session_cookie(cookie_str)
      if token != "" do
        let _ = delete_session(pool, token)
        HTTP.response_with_headers(200, json { status: "logged out" }, clear_cookie)
      else
        HTTP.response_with_headers(200, json { status: "logged out" }, clear_cookie)
      end
    end
  end
end

# HTTP middleware: validate mesher_session cookie on every request.
fn auth_middleware(pool) do
  fn(request, next) do
    let cookie = Request.header(request, "cookie")
    case cookie do
      None -> respond_unauthorized()
      Some(cookie_str) -> do
        let token = parse_session_cookie(cookie_str)
        if token == "" do
          respond_unauthorized()
        else
          let session_result = validate_session(pool, token)
          case session_result do
            Err(_) -> respond_unauthorized()
            Ok(_) -> next(request)
          end
        end
      end
    end
  end
end

# Tier gate: block SaaS-only routes when MESHER_TIER != "saas".
fn tier_gate(request, next) -> Response do
  let tier = Env.get("MESHER_TIER", "oss")
  let path = Request.path(request)
  let cond = String.starts_with(path, "/api/v1/ai/") && tier != "saas"
  if cond do
    respond_saas_only()
  else
    next(request)
  end
end

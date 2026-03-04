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
    let parts = raw_val |> String.split(";")
    parts |> List.head() |> String.trim()
  else
    raw_val |> String.trim()
  end
end

# Parse mesher_session cookie value from cookie header string.
fn parse_session_cookie(cookie_str :: String) -> String do
  if String.contains(cookie_str, "mesher_session=") do
    let parts = cookie_str |> String.split("mesher_session=")
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

fn parse_login_payload(request) -> Map<String, String>!String do
  let raw_body = Request.body(request)
  case Json.parse(raw_body) do
    Err(_) -> Err("invalid_json")
    Ok(body) -> do
      let email = body |> Json.get("email")
      let password = body |> Json.get("password")
      Ok(%{"email" => email, "password" => password})
    end
  end
end

fn authenticate_login_payload(pool, payload :: Map<String, String>) -> Map<String, String>!String do
  let email = payload |> Map.get("email")
  let password = payload |> Map.get("password")
  case authenticate_user(pool, email, password) do
    Err(_) -> Err("invalid_credentials")
    Ok(user_row) -> Ok(user_row)
  end
end

fn create_login_token(pool, user_id :: String) -> String!String do
  let _ = cleanup_expired_sessions(pool)
  case create_session(pool, user_id) do
    Err(_) -> Err("session_creation_failed")
    Ok(token) -> Ok(token)
  end
end

fn execute_login(pool, request) -> Map<String, String>!String do
  let payload = parse_login_payload(request)?
  let user_row_result = payload |2> authenticate_login_payload(pool)
  let user_row = user_row_result?
  let user_id = user_row |> Map.get("id")
  let user_email = user_row |> Map.get("email")
  let token_result = user_id |2> create_login_token(pool)
  let token = token_result?
  Ok(%{"email" => user_email, "token" => token})
end

fn login_error_response(reason :: String) -> Response do
  if reason == "invalid_json" do
    HTTP.response(400, json { error: "invalid JSON" })
  else
    if reason == "invalid_credentials" do
      HTTP.response(401, json { error: "invalid email or password" })
    else
      HTTP.response(500, json { error: "session creation failed" })
    end
  end
end

fn clear_logout_cookie() -> Map<String, String> do
  %{"Set-Cookie" => "mesher_session=; HttpOnly; Path=/; Max-Age=0"}
end

fn maybe_delete_session_from_cookie(pool, cookie_header) do
  case cookie_header do
    None -> ()
    Some(cookie_str) -> do
      let token = parse_session_cookie(cookie_str)
      if token != "" do
        let _ = token |2> delete_session(pool)
      else
        ()
      end
    end
  end
end

fn require_session_token(request) -> String!String do
  let cookie_header = Request.header(request, "cookie")
  case cookie_header do
    None -> Err("unauthorized")
    Some(cookie_str) -> do
      let token = parse_session_cookie(cookie_str)
      if token == "" do
        Err("unauthorized")
      else
        Ok(token)
      end
    end
  end
end

fn require_authenticated_request(pool, request) -> Bool!String do
  let token = require_session_token(request)?
  let _ = validate_session(pool, token)?
  Ok(true)
end

# POST /api/login
pub fn handle_login(pool, request) -> Response do
  case execute_login(pool, request) do
    Err(reason) -> login_error_response(reason)
    Ok(result) -> do
      let user_email = result |> Map.get("email")
      let token = result |> Map.get("token")
      HTTP.response_with_headers(200, json { email: user_email }, %{"Set-Cookie" => "mesher_session=" <> token <> "; HttpOnly; Path=/; SameSite=Lax; Max-Age=86400"})
    end
  end
end

# POST /api/logout
pub fn handle_logout(pool, request) -> Response do
  let _ = Request.header(request, "cookie") |2> maybe_delete_session_from_cookie(pool)
  HTTP.response_with_headers(200, json { status: "logged out" }, clear_logout_cookie())
end

# HTTP middleware: validate mesher_session cookie on every request.
fn auth_middleware(pool) do
  fn(request, next) do
    case require_authenticated_request(pool, request) do
      Err(_) -> respond_unauthorized()
      Ok(_) -> next(request)
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

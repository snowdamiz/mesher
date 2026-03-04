# Password reset flow (AUTH-04)
#
# Implements password reset via time-limited email token (1 hour expiry).
# Tokens are hashed with SHA-256 before storage; raw tokens are sent in emails.
# On confirmation, all user sessions are invalidated to force re-login.
# All data access goes through centralized storage/queries.mpl ORM functions.
# No inline SQL in this module.

from Src.Mail.Sender import send_email
from Src.Storage.Queries import get_user_by_email, invalidate_existing_reset_tokens, create_reset_token, validate_reset_token, mark_reset_token_used, update_user_password, delete_user_sessions

fn reset_success_response() -> Response do
  HTTP.response(200, json { status: "reset email sent" })
end

fn invalid_json_response() -> Response do
  HTTP.response(400, json { error: "invalid JSON" })
end

fn send_reset_email(email :: String, token :: String) -> Response do
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let reset_url = app_url <> "/reset-password?token=" <> token
  let body_text = "Click here to reset your Mesher password: " <> reset_url
  let _ = send_email(email, "Reset your Mesher password", body_text)
  reset_success_response()
end

fn parse_reset_request_email(request) -> String!String do
  let raw_body = Request.body(request)
  case Json.parse(raw_body) do
    Err(_) -> Err("invalid_json")
    Ok(body_json) -> Ok(Json.get(body_json, "email"))
  end
end

fn send_reset_for_known_user(pool, email :: String, user_row :: Map<String, String>) -> Response do
  let user_id = Map.get(user_row, "id")
  let token = Crypto.uuid4()
  let token_hash = Crypto.sha256(token)
  let _ = invalidate_existing_reset_tokens(pool, user_id)
  case create_reset_token(pool, user_id, token_hash) do
    Err(_) -> reset_success_response()
    Ok(_) -> send_reset_email(email, token)
  end
end

fn parse_confirm_payload(request) -> Map<String, String>!String do
  let raw_body = Request.body(request)
  case Json.parse(raw_body) do
    Err(_) -> Err("invalid_json")
    Ok(body_json) -> do
      let token = Json.get(body_json, "token")
      let new_password = Json.get(body_json, "new_password")
      Ok(%{"token" => token, "new_password" => new_password})
    end
  end
end

fn validate_confirm_token(pool, token :: String) -> Map<String, String>!String do
  let token_hash = Crypto.sha256(token)
  case validate_reset_token(pool, token_hash) do
    Err(_) -> Err("invalid_token")
    Ok(token_row) -> Ok(token_row)
  end
end

fn persist_password_reset(pool, token_row :: Map<String, String>, new_password :: String) -> Bool!String do
  let user_id = Map.get(token_row, "user_id")
  let token_id = Map.get(token_row, "id")
  case update_user_password(pool, user_id, new_password) do
    Err(_) -> Err("password_reset_failed")
    Ok(_) -> do
      let _ = mark_reset_token_used(pool, token_id)
      let _ = delete_user_sessions(pool, user_id)
      Ok(true)
    end
  end
end

fn execute_confirm_reset(pool, request) -> Bool!String do
  let payload = parse_confirm_payload(request)?
  let token = Map.get(payload, "token")
  let new_password = Map.get(payload, "new_password")
  let token_row = validate_confirm_token(pool, token)?
  persist_password_reset(pool, token_row, new_password)
end

fn confirm_reset_error_response(reason :: String) -> Response do
  if reason == "invalid_json" do
    invalid_json_response()
  else
    if reason == "invalid_token" do
      HTTP.response(400, json { error: "invalid or expired token" })
    else
      HTTP.response(500, json { error: "password reset failed" })
    end
  end
end

# POST /api/auth/reset-password
pub fn request_reset_handler(pool, request) -> Response do
  case parse_reset_request_email(request) do
    Err(_) -> invalid_json_response()
    Ok(email) -> do
      case get_user_by_email(pool, email) do
        Err(_) -> reset_success_response()
        Ok(user_row) -> send_reset_for_known_user(pool, email, user_row)
      end
    end
  end
end

# POST /api/auth/reset-password/confirm
pub fn confirm_reset_handler(pool, request) -> Response do
  case execute_confirm_reset(pool, request) do
    Err(reason) -> confirm_reset_error_response(reason)
    Ok(_) -> HTTP.response(200, json { status: "password reset" })
  end
end

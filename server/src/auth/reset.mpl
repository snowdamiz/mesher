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

fn send_reset_email(email :: String, token :: String) -> Response do
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let reset_url = app_url <> "/reset-password?token=" <> token
  let body_text = "Click here to reset your Mesher password: " <> reset_url
  let _ = send_email(email, "Reset your Mesher password", body_text)
  reset_success_response()
end

# POST /api/auth/reset-password
pub fn request_reset_handler(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body_json) -> do
      let email = Json.get(body_json, "email")
      let user_result = get_user_by_email(pool, email)
      case user_result do
        Err(_) -> reset_success_response()
        Ok(user_row) -> do
          let user_id = Map.get(user_row, "id")
          let token = Crypto.uuid4()
          let token_hash = Crypto.sha256(token)
          let _ = invalidate_existing_reset_tokens(pool, user_id)
          let create_result = create_reset_token(pool, user_id, token_hash)
          case create_result do
            Err(_) -> reset_success_response()
            Ok(_) -> send_reset_email(email, token)
          end
        end
      end
    end
  end
end

# POST /api/auth/reset-password/confirm
pub fn confirm_reset_handler(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body_json) -> do
      let token = Json.get(body_json, "token")
      let new_password = Json.get(body_json, "new_password")
      let token_hash = Crypto.sha256(token)
      let token_result = validate_reset_token(pool, token_hash)
      case token_result do
        Err(_) -> HTTP.response(400, json { error: "invalid or expired token" })
        Ok(token_row) -> do
          let user_id = Map.get(token_row, "user_id")
          let token_id = Map.get(token_row, "id")
          let pw_result = update_user_password(pool, user_id, new_password)
          case pw_result do
            Err(_) -> HTTP.response(500, json { error: "password reset failed" })
            Ok(_) -> do
              let _ = mark_reset_token_used(pool, token_id)
              let _ = delete_user_sessions(pool, user_id)
              HTTP.response(200, json { status: "password reset" })
            end
          end
        end
      end
    end
  end
end

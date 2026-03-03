import Mail.Sender

# Password reset flow (AUTH-04)
#
# Implements password reset via time-limited email token (1 hour expiry).
# Tokens are hashed with SHA-256 before storage; raw tokens are sent in emails.
# On confirmation, all user sessions are invalidated to force re-login.
#
# CRYPTO NOTE: Mesh Crypto stdlib provides uuid4(), sha256(), sha512(), hmac.
# UUID and SHA-256 use native Mesh Crypto. bcrypt password hashing is delegated
# to PostgreSQL pgcrypto crypt()/gen_salt() since bcrypt is not in Mesh stdlib.
#
# Functions MUST be defined before use (no forward references).
# Case arm expressions MUST be on same line as -> (no multi-line bodies).

# ---------------------------------------------------------------------------
# POST /api/auth/reset-password helpers (strict bottom-up: leaves first)
# ---------------------------------------------------------------------------

fn reset_success_response() -> Response do
  HTTP.response(200, json { status: "reset email sent" })
end

fn send_reset_email(email :: String, token :: String) -> Response do
  let app_url = Env.get("APP_URL", "http://localhost:8080")
  let reset_url = app_url <> "/reset-password?token=" <> token
  let body_text = "Click here to reset your Mesher password: " <> reset_url
  let _ = Sender.send_email(email, "Reset your Mesher password", body_text)
  reset_success_response()
end

fn insert_reset_token(pool, user_id :: String, email :: String, token :: String, token_hash :: String) -> Response do
  let _ = Pool.execute(pool, "UPDATE password_reset_tokens SET used_at = NOW() WHERE user_id = $1 AND used_at IS NULL", [user_id])
  let reset_id = Crypto.uuid4()
  let insert_result = Pool.execute(pool, "INSERT INTO password_reset_tokens (id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, NOW() + INTERVAL '1 hour')", [reset_id, user_id, token_hash])
  case insert_result do
    Err(_) -> reset_success_response()
    Ok(_) -> send_reset_email(email, token)
  end
end

fn generate_token_and_store(pool, user_id :: String, email :: String) -> Response do
  let token = Crypto.uuid4()
  let token_hash = Crypto.sha256(token)
  insert_reset_token(pool, user_id, email, token, token_hash)
end

fn handle_user_lookup(pool, email :: String, rows) -> Response do
  let count = List.length(rows)
  if count == 0 do
    reset_success_response()
  else
    generate_token_and_store(pool, Map.get(List.head(rows), "id"), email)
  end
end

fn lookup_user_and_reset(pool, email :: String) -> Response do
  let user_result = Pool.query(pool, "SELECT id FROM users WHERE email = $1", [email])
  case user_result do
    Err(_) -> reset_success_response()
    Ok(rows) -> handle_user_lookup(pool, email, rows)
  end
end

fn parse_reset_request_body(pool, body_json) -> Response do
  let email = Json.get(body_json, "email")
  lookup_user_and_reset(pool, email)
end

# POST /api/auth/reset-password
pub fn request_reset_handler(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body_json) -> parse_reset_request_body(pool, body_json)
  end
end

# ---------------------------------------------------------------------------
# POST /api/auth/reset-password/confirm helpers (strict bottom-up)
# ---------------------------------------------------------------------------

fn invalidate_sessions_and_respond(pool, user_id :: String) -> Response do
  let _ = Pool.execute(pool, "DELETE FROM sessions WHERE user_id = $1", [user_id])
  HTTP.response(200, json { status: "password reset" })
end

fn mark_token_used(pool, user_id :: String, token_id :: String) -> Response do
  let _ = Pool.execute(pool, "UPDATE password_reset_tokens SET used_at = NOW() WHERE id = $1", [token_id])
  invalidate_sessions_and_respond(pool, user_id)
end

fn update_user_password(pool, user_id :: String, token_id :: String, pw_hash :: String, new_salt :: String) -> Response do
  let update_result = Pool.execute(pool, "UPDATE users SET password_hash = $1, password_salt = $2, updated_at = NOW() WHERE id = $3", [pw_hash, new_salt, user_id])
  case update_result do
    Err(_) -> HTTP.response(500, json { error: "password reset failed" })
    Ok(_) -> mark_token_used(pool, user_id, token_id)
  end
end

fn hash_new_password(pool, user_id :: String, token_id :: String, new_password :: String, new_salt :: String) -> Response do
  let pw_result = Pool.query(pool, "SELECT crypt($1, gen_salt('bf')) AS pw_hash", [new_password])
  case pw_result do
    Err(_) -> HTTP.response(500, json { error: "password reset failed" })
    Ok(pw_rows) -> update_user_password(pool, user_id, token_id, Map.get(List.head(pw_rows), "pw_hash"), new_salt)
  end
end

fn generate_salt_and_hash(pool, user_id :: String, token_id :: String, new_password :: String) -> Response do
  let new_salt = Crypto.uuid4()
  hash_new_password(pool, user_id, token_id, new_password, new_salt)
end

fn check_token_rows(pool, token_rows, new_password :: String) -> Response do
  let count = List.length(token_rows)
  if count == 0 do
    HTTP.response(400, json { error: "invalid or expired token" })
  else
    generate_salt_and_hash(pool, Map.get(List.head(token_rows), "user_id"), Map.get(List.head(token_rows), "id"), new_password)
  end
end

fn lookup_token(pool, token_hash :: String, new_password :: String) -> Response do
  let token_result = Pool.query(pool, "SELECT t.id, t.user_id FROM password_reset_tokens t WHERE t.token_hash = $1 AND t.expires_at > NOW() AND t.used_at IS NULL", [token_hash])
  case token_result do
    Err(_) -> HTTP.response(400, json { error: "invalid or expired token" })
    Ok(token_rows) -> check_token_rows(pool, token_rows, new_password)
  end
end

fn validate_token(pool, token :: String, new_password :: String) -> Response do
  let token_hash = Crypto.sha256(token)
  lookup_token(pool, token_hash, new_password)
end

fn parse_confirm_body(pool, body_json) -> Response do
  let token = Json.get(body_json, "token")
  let new_password = Json.get(body_json, "new_password")
  validate_token(pool, token, new_password)
end

# POST /api/auth/reset-password/confirm
pub fn confirm_reset_handler(pool, request) -> Response do
  let raw_body = Request.body(request)
  let parse_result = Json.parse(raw_body)
  case parse_result do
    Err(_) -> HTTP.response(400, json { error: "invalid JSON" })
    Ok(body_json) -> parse_confirm_body(pool, body_json)
  end
end

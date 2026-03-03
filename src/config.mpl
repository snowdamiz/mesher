# Mesher configuration module
# All runtime configuration is loaded from environment variables.
# Default values are provided for local development.

module Config do
  pub fn database_url() -> String do
    Env.get("DATABASE_URL", "postgres://mesh:mesh@localhost:5432/mesher")
  end

  pub fn session_secret() -> String do
    Env.get("SESSION_SECRET", "dev-secret-change-in-production")
  end

  pub fn tier() -> String do
    Env.get("MESHER_TIER", "oss")
  end

  pub fn is_saas() -> Bool do
    tier() == "saas"
  end

  pub fn http_port() -> Int do
    Env.get_int("HTTP_PORT", 8080)
  end

  pub fn valkey_url() -> String do
    Env.get("VALKEY_URL", "valkey://localhost:6379")
  end

  pub fn smtp_host() -> String do
    Env.get("SMTP_HOST", "")
  end

  pub fn smtp_port() -> Int do
    Env.get_int("SMTP_PORT", 587)
  end

  pub fn smtp_user() -> String do
    Env.get("SMTP_USER", "")
  end

  pub fn smtp_pass() -> String do
    Env.get("SMTP_PASS", "")
  end

  pub fn google_client_id() -> String do
    Env.get("GOOGLE_CLIENT_ID", "")
  end

  pub fn google_client_secret() -> String do
    Env.get("GOOGLE_CLIENT_SECRET", "")
  end
end

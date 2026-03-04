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

  pub fn smtp_from() -> String do
    Env.get("SMTP_FROM", "noreply@mesher.local")
  end

  pub fn app_url() -> String do
    Env.get("APP_URL", "http://localhost:8080")
  end

  pub fn password_reset_expiry_minutes() -> Int do
    Env.get_int("PASSWORD_RESET_EXPIRY_MINUTES", 60)
  end

  pub fn google_client_id() -> String do
    Env.get("GOOGLE_CLIENT_ID", "")
  end

  pub fn google_client_secret() -> String do
    Env.get("GOOGLE_CLIENT_SECRET", "")
  end

  # Ingestion configuration
  pub fn otlp_port() -> Int do
    Env.get_int("OTLP_PORT", 4318)
  end

  pub fn rate_limit_default_per_minute() -> Int do
    Env.get_int("RATE_LIMIT_DEFAULT_PER_MINUTE", 1000)
  end

  pub fn rate_limit_default_burst() -> Int do
    Env.get_int("RATE_LIMIT_DEFAULT_BURST", 100)
  end
end

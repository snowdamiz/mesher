# Ingestion pipeline health endpoint.
#
# Reports overall ingestion health based on component checks:
#   - Database: SELECT 1 connectivity check
#   - Rate limiter: Valkey availability (currently always "unavailable" since
#     Mesh has no Valkey client; rate limiting falls back to PostgreSQL)
#
# Status levels:
#   - healthy:     All systems operational
#   - degraded:    Some systems impaired but ingestion works (e.g., rate limiter down)
#   - unavailable: Critical failure (e.g., database unreachable)
#
# HTTP response codes:
#   - 200 for healthy and degraded (ingestion can still accept events)
#   - 503 for unavailable (ingestion cannot function)

from Src.Ingest.Ratelimit import connect_valkey

# Check database connectivity by running a simple query.
# Returns "ok" on success, "unavailable" on failure.
fn check_db(pool :: PoolHandle) -> String do
  let result = Repo.query_raw(pool, "SELECT 1 AS ok", [])
  case result do
    Ok(_) -> "ok"
    Err(_) -> "unavailable"
  end
end

# Check rate limiter (Valkey) connectivity.
# Returns "ok" if Valkey is reachable, "unavailable" otherwise.
# Currently always returns "unavailable" since Mesh has no Valkey client.
# When Valkey support is added, this will attempt a connection/ping.
fn check_rate_limiter() -> String do
  let url = Env.get("VALKEY_URL", "valkey://localhost:6379")
  let result = connect_valkey(url)
  case result do
    Ok(_) -> "ok"
    Err(_) -> "unavailable"
  end
end

# Determine overall status from component statuses.
# unavailable if DB is down; degraded if rate limiter is down; healthy otherwise.
fn compute_status(db_status :: String, rl_status :: String) -> String do
  if db_status == "unavailable" do
    "unavailable"
  else if rl_status == "unavailable" do
    "degraded"
  else
    "healthy"
  end
end

# Determine HTTP status code from overall status.
# 503 for unavailable, 200 for healthy/degraded.
fn status_code(status :: String) -> Int do
  if status == "unavailable" do 503 else 200 end
end

# GET /health/ingest
#
# Returns JSON with pipeline status and component health.
# Response format:
#   {"status":"healthy","db":"ok","rate_limiter":"ok"}
#   {"status":"degraded","db":"ok","rate_limiter":"unavailable"}
#   {"status":"unavailable","db":"unavailable","rate_limiter":"unknown"}
pub fn handle_health_ingest(pool :: PoolHandle, request) -> Response do
  let db_status = check_db(pool)
  let rl_status = check_rate_limiter()
  let status = compute_status(db_status, rl_status)
  let code = status_code(status)
  HTTP.response(code, json { status: status, db: db_status, rate_limiter: rl_status })
end

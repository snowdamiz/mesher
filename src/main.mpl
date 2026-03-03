# Mesher application entry point
# Starts the HTTP server with a connection pool, health endpoint,
# and authentication routes (login/logout).
#
# Auth routes call handle_login and handle_logout from src/auth/session.mpl.
# These functions are compiled in the same build unit (src/ directory).

fn main() do
  # Open database connection pool
  # Args: url, min_connections, max_connections, timeout_ms
  let db_url = Env.get("DATABASE_URL", "postgres://mesh:mesh@localhost:5432/mesher")
  let port = Env.get_int("HTTP_PORT", 8080)
  let pool = Pool.open(db_url, 2, 10, 5000)?

  # Create HTTP router with health and auth routes
  let router = HTTP.router()
    |> HTTP.on_get("/health", fn(request) do
      HTTP.response(200, json { status: "ok" })
    end)
    # Auth routes (public -- no session required)
    |> HTTP.on_post("/api/login", fn(request) do
      handle_login(pool, request)
    end)
    |> HTTP.on_post("/api/logout", fn(request) do
      handle_logout(pool, request)
    end)

  # Start HTTP server
  HTTP.serve(router, port)
end

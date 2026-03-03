# Mesher application entry point
# Starts the HTTP server with a connection pool and basic health endpoint.
# Subsequent plans will add routes, middleware, and WebSocket handlers.

fn main() do
  # Open database connection pool
  # Args: url, min_connections, max_connections, timeout_ms
  let db_url = Env.get("DATABASE_URL", "postgres://mesh:mesh@localhost:5432/mesher")
  let port = Env.get_int("HTTP_PORT", 8080)
  let pool = Pool.open(db_url, 2, 10, 5000)?

  # Create HTTP router with health endpoint
  let router = HTTP.router()
    |> HTTP.on_get("/health", fn(request) do
      HTTP.response(200, json { status: "ok" })
    end)

  # Start HTTP server
  HTTP.serve(router, port)
end

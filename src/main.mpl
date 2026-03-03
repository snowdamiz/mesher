# Mesher application entry point
# Starts the HTTP server with a connection pool and basic health endpoint.
# Subsequent plans will add routes, middleware, and WebSocket handlers.

from Config import database_url, http_port

fn main() do
  # Open database connection pool
  # Args: url, min_connections, max_connections, timeout_ms
  let pool = Pool.open(Config.database_url(), 2, 10, 5000)?

  # Create HTTP router with health endpoint
  let router = HTTP.router()
    |> HTTP.on_get("/health", fn(request) do
      HTTP.response(200, json { status: "ok" })
    end)

  # Start HTTP server
  HTTP.serve(router, Config.http_port())
end

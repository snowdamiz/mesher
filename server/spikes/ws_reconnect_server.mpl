# WebSocket Reconnection Test Server
#
# Companion server for spikes/ws_reconnect.test.html
# Start this server before opening the HTML test page.
#
# Run: meshc run spikes/ws_reconnect_server.mpl
#
# Listens on port 9902. When a client sends "drop", the server
# sends a close frame to simulate a server-side disconnect.
# The Streem-2 fromWebSocket() should automatically reconnect.

fn on_connect(conn, _path, _headers) do
  let _ = Ws.send(conn, "connected")
  0
end

fn on_message(conn, msg) do
  if msg == "drop" do
    let _ = Ws.send(conn, "dropping")
    # Connection will close when this handler returns
    # The WS actor for this connection exits, triggering client-side close
    println("dropping client connection")
  else
    let _ = Ws.send(conn, msg)
    println("echoed message")
  end
end

fn on_close(_conn, _code, _reason) do
  println("client disconnected")
end

fn main() do
  println("Starting WebSocket reconnect test server on port 9902...")
  Ws.serve(on_connect, on_message, on_close, 9902)
end

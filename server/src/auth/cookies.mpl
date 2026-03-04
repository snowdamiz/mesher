# Shared cookie parsing for session-based authentication.
# Extracts user_id from the mesher_session cookie via DB lookup.
#
# Used by: Org.Handlers, Org.Invites, Project.Projects

from Src.Storage.Queries import validate_session

pub fn session_cookie_header(token :: String) -> String do
  "mesher_session=" <> token <> "; HttpOnly; Path=/; SameSite=Lax; Max-Age=86400"
end

pub fn clear_session_cookie_header() -> String do
  "mesher_session=; HttpOnly; Path=/; Max-Age=0"
end

# Recursive search for mesher_session cookie in parsed pairs.
fn find_session_at_index(pairs, idx :: Int, len :: Int) -> String!String do
  if idx >= len do
    Err("no session cookie")
  else
    let pair = List.get(pairs, idx)
    let trimmed = String.trim(pair)
    if String.starts_with(trimmed, "mesher_session=") do
      Ok(String.slice(trimmed, 16, String.length(trimmed)))
    else
      find_session_at_index(pairs, idx + 1, len)
    end
  end
end

fn find_session_cookie(cookies :: String) -> String!String do
  let pairs = String.split(cookies, ";")
  let len = List.length(pairs)
  if len == 0 do
    Err("no session cookie")
  else
    find_session_at_index(pairs, 0, len)
  end
end

fn validate_session_cookie(pool, session_id :: String) -> String!String do
  let row = validate_session(pool, session_id)?
  Ok(Map.get(row, "user_id"))
end

fn extract_user_from_cookies(pool, cookies :: String) -> String!String do
  let session_id = find_session_cookie(cookies)?
  validate_session_cookie(pool, session_id)
end

pub fn extract_user_id(pool, request) -> String!String do
  let cookie_header = Request.header(request, "cookie")
  case cookie_header do
    None -> Err("no session cookie")
    Some(cookies) -> extract_user_from_cookies(pool, cookies)
  end
end

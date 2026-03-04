# Shared ingest string-based JSON and delimiter matching helpers.
#
# This module centralizes exact duplicate helpers previously defined in
# generic/envelope/otlp ingest handlers.

fn brace_depth_delta(ch :: String, depth :: Int) -> Int do
  if ch == "{" do depth + 1 else if ch == "}" do depth - 1 else depth end
end

fn bracket_depth_delta(ch :: String, depth :: Int) -> Int do
  if ch == "[" do depth + 1 else if ch == "]" do depth - 1 else depth end
end

pub fn find_matching_brace(s :: String, depth :: Int, pos :: Int, len :: Int) -> String do
  if pos >= len do
    String.slice(s, 0, pos)
  else if depth <= 0 do
    String.slice(s, 0, pos)
  else
    let ch = String.slice(s, pos, pos + 1)
    let new_depth = brace_depth_delta(ch, depth)
    if new_depth <= 0 do
      String.slice(s, 0, pos + 1)
    else
      find_matching_brace(s, new_depth, pos + 1, len)
    end
  end
end

pub fn find_matching_bracket(s :: String, depth :: Int, pos :: Int, len :: Int) -> String do
  if pos >= len do
    String.slice(s, 0, pos)
  else if depth <= 0 do
    String.slice(s, 0, pos)
  else
    let ch = String.slice(s, pos, pos + 1)
    let new_depth = bracket_depth_delta(ch, depth)
    if new_depth <= 0 do
      String.slice(s, 0, pos + 1)
    else
      find_matching_bracket(s, new_depth, pos + 1, len)
    end
  end
end

pub fn json_field(json_str :: String, field :: String) -> String do
  let search = "\"" <> field <> "\":\""
  if String.contains(json_str, search) do
    let parts = String.split(json_str, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      let val_parts = String.split(rest, "\"")
      if List.length(val_parts) > 0 do
        List.head(val_parts)
      else
        ""
      end
    else
      ""
    end
  else
    ""
  end
end

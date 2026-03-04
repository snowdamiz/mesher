# Generic JSON API handler for custom integrations.
#
# Provides a simplified JSON API for ingesting error events from
# applications that don't use Sentry SDK or OTLP exporters.
#
# POST /api/:project_id/events
#
# Request format:
#   {
#     "message": "...",           (required)
#     "level": "error",           (optional, default: "error")
#     "environment": "production",(optional, default: "production")
#     "exception": {
#       "type": "TypeError",     (optional)
#       "value": "...",           (optional)
#       "stacktrace": [...]       (optional, array of frame objects)
#     },
#     "tags": {},                 (optional)
#     "extra": {},                (optional)
#     "release": "",              (optional)
#     "server_name": ""           (optional)
#   }
#
# Response: 200 {"id": "<event_id>"}
# Errors: 400 (invalid JSON, missing message), 401 (auth), 429 (rate limit)
#
# Rate-limited responses use HTTP.response_with_headers with Retry-After header.

from Src.Ingest.Auth import extract_and_validate_api_key
from Src.Ingest.Scrubber import scrub_event_fields
from Src.Ingest.Fingerprint import compute_fingerprint
from Src.Ingest.Ratelimit import check_rate_limit
from Src.Storage.Queries import upsert_issue, insert_event

# ============================================================================
# String-based JSON helpers (shared patterns from envelope/otlp handlers)
# ============================================================================

# Extract a string field value from JSON: "field":"value" -> value
fn json_field(json_str :: String, field :: String) -> String do
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

# Extract a JSON object field as raw string: "field":{...} -> {...}
# Uses brace depth tracking to find the matching closing brace.
fn extract_json_object(json_str :: String, field :: String) -> String do
  let search = "\"" <> field <> "\":{"
  if String.contains(json_str, search) do
    let parts = String.split(json_str, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      let result = find_matching_brace(rest, 1, 0, String.length(rest))
      "{" <> result
    else
      "{}"
    end
  else
    "{}"
  end
end

# Compute brace depth delta for a character.
fn brace_delta(ch :: String, depth :: Int) -> Int do
  if ch == "{" do depth + 1 else if ch == "}" do depth - 1 else depth end
end

# Find matching closing brace by tracking depth.
fn find_matching_brace(s :: String, depth :: Int, pos :: Int, len :: Int) -> String do
  if pos >= len do
    String.slice(s, 0, pos)
  else if depth <= 0 do
    String.slice(s, 0, pos)
  else
    let ch = String.slice(s, pos, pos + 1)
    let new_depth = brace_delta(ch, depth)
    if new_depth <= 0 do
      String.slice(s, 0, pos + 1)
    else
      find_matching_brace(s, new_depth, pos + 1, len)
    end
  end
end

# Extract a JSON array field as raw string: "field":[...] -> [...]
fn extract_json_array(json_str :: String, field :: String) -> String do
  let search = "\"" <> field <> "\":["
  if String.contains(json_str, search) do
    let parts = String.split(json_str, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      let result = find_matching_bracket(rest, 1, 0, String.length(rest))
      "[" <> result
    else
      "[]"
    end
  else
    "[]"
  end
end

# Compute bracket depth delta.
fn bracket_delta(ch :: String, depth :: Int) -> Int do
  if ch == "[" do depth + 1 else if ch == "]" do depth - 1 else depth end
end

# Find matching closing bracket by tracking depth.
fn find_matching_bracket(s :: String, depth :: Int, pos :: Int, len :: Int) -> String do
  if pos >= len do
    String.slice(s, 0, pos)
  else if depth <= 0 do
    String.slice(s, 0, pos)
  else
    let ch = String.slice(s, pos, pos + 1)
    let new_depth = bracket_delta(ch, depth)
    if new_depth <= 0 do
      String.slice(s, 0, pos + 1)
    else
      find_matching_bracket(s, new_depth, pos + 1, len)
    end
  end
end

# ============================================================================
# Response helpers
# ============================================================================

# Return rate limit 429 response with Retry-After header.
fn generic_rate_limit_response(retry_val :: String) -> Response do
  let headers = %{"Retry-After" => retry_val}
  HTTP.response_with_headers(429, json { error: "rate limit exceeded" }, headers)
end

# Truncate a string to a maximum length.
fn truncate_str(s :: String, max_len :: Int) -> String do
  if String.length(s) > max_len do
    String.slice(s, 0, max_len)
  else
    s
  end
end

# ============================================================================
# Main handler
# ============================================================================

# POST /api/:project_id/events
#
# Accepts a simplified JSON event payload for custom integrations.
# Pipeline: authenticate -> rate limit -> parse -> scrub -> fingerprint
#           -> upsert issue -> insert event -> 200 response
#
# Returns: 200 {"id": "<event_id>"}
# Errors:
#   - 400: invalid JSON or missing required "message" field
#   - 401: invalid or missing API key
#   - 429: rate limited (with Retry-After header)
pub fn handle_generic_event(pool :: PoolHandle, request) -> Response do
  # 1. Auth: extract_and_validate_api_key (Bearer token)
  let auth_result = extract_and_validate_api_key(pool, request)
  case auth_result do
    Err(msg) -> HTTP.response(401, json { error: msg })
    Ok(auth) -> do
      let project_id = Map.get(auth, "project_id")
      let org_id = Map.get(auth, "org_id")

      # 2. Rate limit check (default 1000 events/minute)
      let rl = check_rate_limit(pool, org_id, 1000)
      let allowed = Map.get(rl, "allowed")
      if allowed == "false" do
        let retry_val = Map.get(rl, "retry_after")
        generic_rate_limit_response(retry_val)
      else
        # 3. Parse JSON body
        let raw_body = Request.body(request)
        if raw_body == "" do
          HTTP.response(400, json { error: "invalid JSON" })
        else
          # Validate basic JSON structure
          let trimmed = String.trim(raw_body)
          if !String.starts_with(trimmed, "{") do
            HTTP.response(400, json { error: "invalid JSON" })
          else
            # Extract fields from the JSON body
            let message = json_field(trimmed, "message")
            if message == "" do
              HTTP.response(400, json { error: "message is required" })
            else
              # Extract optional fields with defaults
              let level_raw = json_field(trimmed, "level")
              let level = if level_raw == "" do "error" else level_raw end
              let env_raw = json_field(trimmed, "environment")
              let environment = if env_raw == "" do "production" else env_raw end
              let release = json_field(trimmed, "release")
              let server_name = json_field(trimmed, "server_name")

              # Extract exception object fields
              let exception_obj = extract_json_object(trimmed, "exception")
              let exception_type = json_field(exception_obj, "type")
              let exception_value = json_field(exception_obj, "value")
              let stacktrace_json = extract_json_array(exception_obj, "stacktrace")

              # Extract tags and extra as raw JSON strings
              let tags_json = extract_json_object(trimmed, "tags")
              let extra_json = extract_json_object(trimmed, "extra")

              # 4. Generate event_id
              let event_id = Crypto.uuid4()

              # 5. Scrub all fields
              let scrub_result = scrub_event_fields(pool, org_id, message, exception_value, stacktrace_json, tags_json, extra_json, "{}", server_name)
              case scrub_result do
                Err(_) -> HTTP.response(500, json { error: "internal error" })
                Ok(scrubbed) -> do
                  let s_message = Map.get(scrubbed, "message")
                  let s_exception_value = Map.get(scrubbed, "exception_value")
                  let s_stacktrace_json = Map.get(scrubbed, "stacktrace_json")
                  let s_tags_json = Map.get(scrubbed, "tags_json")
                  let s_extra_json = Map.get(scrubbed, "extra_json")
                  let s_server_name = Map.get(scrubbed, "server_name")

                  # 6. Compute fingerprint
                  let fingerprint = compute_fingerprint(exception_type, s_stacktrace_json)

                  # 7. Build title and upsert issue
                  let title_raw = if exception_type != "" && s_exception_value != "" do
                    exception_type <> ": " <> s_exception_value
                  else if exception_type != "" do
                    exception_type
                  else
                    s_message
                  end
                  let title = truncate_str(title_raw, 255)

                  let issue_result = upsert_issue(pool, project_id, fingerprint, title, level)
                  case issue_result do
                    Err(_) -> HTTP.response(500, json { error: "internal error" })
                    Ok(issue_row) -> do
                      let issue_id = Map.get(issue_row, "id")

                      # 8. Insert event
                      let event_result = insert_event(pool, project_id, issue_id, event_id, "now()", "generic", level, s_message, exception_type, s_exception_value, s_stacktrace_json, environment, release, s_server_name, s_tags_json, s_extra_json, "{}", "generic-api", "1.0", fingerprint)
                      case event_result do
                        Err(_) -> HTTP.response(500, json { error: "internal error" })
                        Ok(_) -> HTTP.response(200, json { id: event_id })
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

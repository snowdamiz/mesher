# Sentry envelope parser and HTTP handler.
#
# Implements the Sentry envelope format (POST /api/:project_id/envelope/)
# for drop-in @sentry/node SDK compatibility. Users change only their DSN
# string to point at Mesher.
#
# Envelope format (newline-delimited):
#   Line 1: envelope header JSON (event_id, dsn, sent_at, sdk)
#   Line 2: item header JSON (type, length)
#   Line 3+: item payload (JSON for events)
#   (repeat for additional items)
#
# Pipeline: authenticate -> rate limit -> parse -> scrub -> fingerprint
#           -> upsert issue -> insert event -> 200 response
#
# Non-event item types (attachment, session, transaction, check_in, statsd,
# profile, replay_event, replay_recording, feedback) are silently discarded
# per locked decision. Envelope still returns 200.
#
# Rate-limited responses return 429 with Retry-After and X-Sentry-Rate-Limits
# headers via HTTP.response_with_headers.

from Src.Ingest.Auth import extract_and_validate_api_key
from Src.Ingest.Scrubber import scrub_event_fields
from Src.Ingest.Fingerprint import compute_fingerprint
from Src.Ingest.Ratelimit import check_rate_limit, compute_retry_after
from Src.Storage.Queries import upsert_issue, insert_event, get_rate_limit_config

# ============================================================================
# Envelope header parsing
# ============================================================================

# Extract a string field value from a JSON string by key name.
# Looks for "key":"value" pattern.
fn json_string_field(json_str :: String, field :: String) -> String do
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

# Extract a nested string field value from a JSON string.
# E.g., for sdk.name, looks for "name":" inside the "sdk":{...} block.
# This simplified approach just looks for the field globally after the parent key.
fn json_nested_string_field(json_str :: String, parent :: String, field :: String) -> String do
  let parent_search = "\"" <> parent <> "\":{"
  if String.contains(json_str, parent_search) do
    let parts = String.split(json_str, parent_search)
    if List.length(parts) >= 2 do
      let nested_json = List.last(parts)
      json_string_field(nested_json, field)
    else
      ""
    end
  else
    ""
  end
end

# Parse the envelope header (first line of the envelope).
# Extracts: event_id, sdk_name, sdk_version, sent_at
fn parse_envelope_header(header_line :: String) -> Map<String, String>!String do
  let trimmed = String.trim(header_line)
  if trimmed == "" do
    Err("empty envelope header")
  else
    let event_id = json_string_field(trimmed, "event_id")
    let sent_at = json_string_field(trimmed, "sent_at")
    let sdk_name = json_nested_string_field(trimmed, "sdk", "name")
    let sdk_version = json_nested_string_field(trimmed, "sdk", "version")
    Ok(%{"event_id" => event_id, "sent_at" => sent_at, "sdk_name" => sdk_name, "sdk_version" => sdk_version})
  end
end

# ============================================================================
# Item header parsing
# ============================================================================

# Parse an item header line. Extracts: type, length (optional).
fn parse_item_header(header_line :: String) -> Map<String, String>!String do
  let trimmed = String.trim(header_line)
  if trimmed == "" do
    Err("empty item header")
  else
    let item_type = json_string_field(trimmed, "type")
    let item_length = json_string_field(trimmed, "length")
    Ok(%{"type" => item_type, "length" => item_length})
  end
end

# ============================================================================
# Exception data extraction from Sentry event JSON
# ============================================================================

# Extract an object field as raw JSON string from a larger JSON string.
# For example, extract the value of "tags":{...} as a raw string.
fn extract_json_object(json_str :: String, field :: String) -> String do
  let search = "\"" <> field <> "\":{"
  if String.contains(json_str, search) do
    let parts = String.split(json_str, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      # Find the matching closing brace (simplified: count braces)
      let result = find_matching_brace(rest, 1, 0, String.length(rest))
      "{" <> result
    else
      "{}"
    end
  else
    "{}"
  end
end

# Compute updated brace depth for a single character.
fn brace_depth_delta(ch :: String, depth :: Int) -> Int do
  if ch == "{" do depth + 1 else if ch == "}" do depth - 1 else depth end
end

# Find the matching closing brace by tracking brace depth.
fn find_matching_brace(s :: String, depth :: Int, pos :: Int, len :: Int) -> String do
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

# Extract the frames array from the exception stacktrace.
# Looks for "frames":[ and extracts the array content.
fn extract_frames_json(event_json :: String) -> String do
  let search = "\"frames\":["
  if String.contains(event_json, search) do
    let parts = String.split(event_json, search)
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

# Compute updated bracket depth for a single character.
fn bracket_depth_delta(ch :: String, depth :: Int) -> Int do
  if ch == "[" do depth + 1 else if ch == "]" do depth - 1 else depth end
end

# Find the matching closing bracket by tracking bracket depth.
fn find_matching_bracket(s :: String, depth :: Int, pos :: Int, len :: Int) -> String do
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

# Extract the exception type and value from the first exception in the chain.
# Sentry event JSON has exception.values[0].type and exception.values[0].value.
fn extract_exception_type(event_json :: String) -> String do
  let search = "\"values\":["
  if String.contains(event_json, search) do
    let parts = String.split(event_json, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      json_string_field(rest, "type")
    else
      ""
    end
  else
    ""
  end
end

fn extract_exception_value(event_json :: String) -> String do
  let search = "\"values\":["
  if String.contains(event_json, search) do
    let parts = String.split(event_json, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      json_string_field(rest, "value")
    else
      ""
    end
  else
    ""
  end
end

# Extract all event fields from a Sentry event JSON payload.
# Returns a map with: exception_type, exception_value, stacktrace_json,
# platform, level, environment, release, server_name, tags_json, extra_json,
# contexts_json, message, timestamp
fn extract_exception_data(event_json :: String) -> Map<String, String> do
  let exception_type = extract_exception_type(event_json)
  let exception_value = extract_exception_value(event_json)
  let stacktrace_json = extract_frames_json(event_json)
  let platform = json_string_field(event_json, "platform")
  let level = json_string_field(event_json, "level")
  let environment = json_string_field(event_json, "environment")
  let release = json_string_field(event_json, "release")
  let server_name = json_string_field(event_json, "server_name")
  let message = json_string_field(event_json, "message")
  let timestamp_str = json_string_field(event_json, "timestamp")
  let tags_json = extract_json_object(event_json, "tags")
  let extra_json = extract_json_object(event_json, "extra")
  let contexts_json = extract_json_object(event_json, "contexts")
  # Use defaults for empty required fields
  let final_platform = if platform == "" do "unknown" else platform end
  let final_level = if level == "" do "error" else level end
  let final_environment = if environment == "" do "production" else environment end
  let final_timestamp = if timestamp_str == "" do "now" else timestamp_str end
  %{"exception_type" => exception_type, "exception_value" => exception_value, "stacktrace_json" => stacktrace_json, "platform" => final_platform, "level" => final_level, "environment" => final_environment, "release" => release, "server_name" => server_name, "message" => message, "timestamp" => final_timestamp, "tags_json" => tags_json, "extra_json" => extra_json, "contexts_json" => contexts_json}
end

# ============================================================================
# Rate limit response helper
# ============================================================================

# Build a 429 rate-limit response with Sentry-compatible headers.
# Per locked decision: return X-Sentry-Rate-Limits and Retry-After on 429.
fn rate_limit_response(retry_str :: String) -> Response do
  let headers = %{"Retry-After" => retry_str, "X-Sentry-Rate-Limits" => retry_str <> ":error:scope"}
  HTTP.response_with_headers(429, json { error: "rate limit exceeded", retry_after: retry_str }, headers)
end

# ============================================================================
# Envelope item processing helpers
# ============================================================================

# Check if an item type is processable (event or error).
fn is_processable_type(item_type :: String) -> Bool do
  item_type == "event" || item_type == "error"
end

# Truncate a string to a maximum length.
fn truncate_string(s :: String, max_len :: Int) -> String do
  if String.length(s) > max_len do
    String.slice(s, 0, max_len)
  else
    s
  end
end

# Build an issue title from exception type and value.
# Format: "ExceptionType: exception message" truncated to 255 chars.
fn build_issue_title(exception_type :: String, exception_value :: String) -> String do
  let title = if exception_type != "" && exception_value != "" do
    exception_type <> ": " <> exception_value
  else if exception_type != "" do
    exception_type
  else if exception_value != "" do
    exception_value
  else
    "Unknown Error"
  end
  truncate_string(title, 255)
end

# ============================================================================
# Process a single event item through the scrub/fingerprint/store pipeline
# ============================================================================

# Process a single event: scrub -> fingerprint -> upsert issue -> insert event.
# Returns the event_id on success.
fn process_event_item(pool :: PoolHandle, project_id :: String, org_id :: String, event_id :: String, event_json :: String, sdk_name :: String, sdk_version :: String) -> String!String do
  let data = extract_exception_data(event_json)
  let exception_type = Map.get(data, "exception_type")
  let exception_value = Map.get(data, "exception_value")
  let stacktrace_json = Map.get(data, "stacktrace_json")
  let platform = Map.get(data, "platform")
  let level = Map.get(data, "level")
  let environment = Map.get(data, "environment")
  let release = Map.get(data, "release")
  let server_name = Map.get(data, "server_name")
  let message = Map.get(data, "message")
  let timestamp_val = Map.get(data, "timestamp")
  let tags_json = Map.get(data, "tags_json")
  let extra_json = Map.get(data, "extra_json")
  let contexts_json = Map.get(data, "contexts_json")
  # Step 1: Scrub PII from all string fields
  let scrubbed = scrub_event_fields(pool, org_id, message, exception_value, stacktrace_json, tags_json, extra_json, contexts_json, server_name)?
  let s_message = Map.get(scrubbed, "message")
  let s_exception_value = Map.get(scrubbed, "exception_value")
  let s_stacktrace_json = Map.get(scrubbed, "stacktrace_json")
  let s_tags_json = Map.get(scrubbed, "tags_json")
  let s_extra_json = Map.get(scrubbed, "extra_json")
  let s_contexts_json = Map.get(scrubbed, "contexts_json")
  let s_server_name = Map.get(scrubbed, "server_name")
  # Step 2: Compute fingerprint AFTER scrubbing (per RESEARCH.md)
  let fingerprint = compute_fingerprint(exception_type, s_stacktrace_json)
  # Step 3: Upsert issue by fingerprint
  let title = build_issue_title(exception_type, s_exception_value)
  let issue_result = upsert_issue(pool, project_id, fingerprint, title, level)?
  let issue_id = Map.get(issue_result, "id")
  # Step 4: Insert event
  let ts = if timestamp_val == "now" do "now()" else timestamp_val end
  let _ = insert_event(pool, project_id, issue_id, event_id, ts, platform, level, s_message, exception_type, s_exception_value, s_stacktrace_json, environment, release, s_server_name, s_tags_json, s_extra_json, s_contexts_json, sdk_name, sdk_version, fingerprint)?
  Ok(event_id)
end

# ============================================================================
# Envelope body parsing: iterate over items in pairs
# ============================================================================

# Process envelope items starting at the given line index.
# Items come in pairs: item header line + payload line.
# Returns the event_id of the first processed event, or "" if none.
fn process_items(pool :: PoolHandle, project_id :: String, org_id :: String, envelope_event_id :: String, lines :: List<String>, idx :: Int, total_lines :: Int, sdk_name :: String, sdk_version :: String, first_event_id :: String) -> String!String do
  if idx >= total_lines do
    Ok(first_event_id)
  else
    let header_line = List.get(lines, idx)
    let payload_idx = idx + 1
    if payload_idx >= total_lines do
      Ok(first_event_id)
    else
      let payload_line = List.get(lines, payload_idx)
      let item_header_result = parse_item_header(header_line)
      case item_header_result do
        Err(_) -> process_items(pool, project_id, org_id, envelope_event_id, lines, idx + 2, total_lines, sdk_name, sdk_version, first_event_id)
        Ok(item_header) -> do
          let item_type = Map.get(item_header, "type")
          let is_processable = is_processable_type(item_type)
          if is_processable do
            let ev_id = if envelope_event_id != "" do envelope_event_id else Crypto.uuid4() end
            let process_result = process_event_item(pool, project_id, org_id, ev_id, payload_line, sdk_name, sdk_version)
            case process_result do
              Ok(processed_id) -> do
                let new_first = if first_event_id == "" do processed_id else first_event_id end
                process_items(pool, project_id, org_id, "", lines, idx + 2, total_lines, sdk_name, sdk_version, new_first)
              end
              Err(_) -> process_items(pool, project_id, org_id, envelope_event_id, lines, idx + 2, total_lines, sdk_name, sdk_version, first_event_id)
            end
          else
            # Silently discard non-event items (locked decision)
            process_items(pool, project_id, org_id, envelope_event_id, lines, idx + 2, total_lines, sdk_name, sdk_version, first_event_id)
          end
        end
      end
    end
  end
end

# ============================================================================
# Main handler
# ============================================================================

# Handle a Sentry envelope POST request.
#
# Pipeline:
#   1. Authenticate via API key (X-Sentry-Auth, query param, or Bearer)
#   2. Check rate limit for the org
#   3. Parse envelope: header + item pairs
#   4. For each event/error item: scrub -> fingerprint -> upsert issue -> insert event
#   5. Silently discard non-event items (attachment, session, etc.)
#   6. Return 200 with event_id in body (Sentry-compatible)
#
# Error responses:
#   - 403: Invalid API key
#   - 429: Rate limited (with Retry-After and X-Sentry-Rate-Limits headers)
#   - 400: Empty or unparseable envelope body
pub fn handle_sentry_envelope(pool :: PoolHandle, request) -> Response do
  # Step 1: Authenticate
  let auth_result = extract_and_validate_api_key(pool, request)
  case auth_result do
    Err(_) -> HTTP.response(403, json { error: "invalid API key" })
    Ok(auth_info) -> do
      let project_id = Map.get(auth_info, "project_id")
      let org_id = Map.get(auth_info, "org_id")
      # Step 2: Rate limit check
      # Rate limit check -- use default 1000 events/minute
      # (Int.parse unavailable in Mesh; config returns string)
      let rl_result = check_rate_limit(pool, org_id, 1000)
      let allowed = Map.get(rl_result, "allowed")
      if allowed != "true" do
        let retry_val = Map.get(rl_result, "retry_after")
        rate_limit_response(retry_val)
      else
        # Step 3: Parse envelope body
        let body = Request.body(request)
        let trimmed_body = String.trim(body)
        if trimmed_body == "" do
          HTTP.response(400, json { error: "empty envelope body" })
        else
          let lines = String.split(trimmed_body, "\n")
          let num_lines = List.length(lines)
          if num_lines < 1 do
            HTTP.response(400, json { error: "invalid envelope format" })
          else
            # Parse envelope header (line 0)
            let header_line = List.head(lines)
            let env_header_result = parse_envelope_header(header_line)
            case env_header_result do
              Err(e) -> HTTP.response(400, json { error: "invalid envelope header" })
              Ok(env_header) -> do
                let envelope_event_id = Map.get(env_header, "event_id")
                let sdk_name = Map.get(env_header, "sdk_name")
                let sdk_version = Map.get(env_header, "sdk_version")
                let event_id_to_use = if envelope_event_id != "" do envelope_event_id else Crypto.uuid4() end
                # Step 4: Process items (starting at line 1, in pairs)
                let process_result = process_items(pool, project_id, org_id, event_id_to_use, lines, 1, num_lines, sdk_name, sdk_version, "")
                case process_result do
                  Ok(first_id) -> do
                    let response_id = if first_id != "" do first_id else event_id_to_use end
                    HTTP.response(200, json { id: response_id })
                  end
                  Err(_) -> do
                    # Even on processing error, return 200 with the event_id
                    # to keep SDK happy (Sentry convention)
                    HTTP.response(200, json { id: event_id_to_use })
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

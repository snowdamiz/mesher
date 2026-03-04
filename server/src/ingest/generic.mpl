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

from Src.Ingest.Helpers import json_field, find_matching_brace, find_matching_bracket
from Src.Ingest.Middleware import validate_ingest_request
from Src.Ingest.Scrubber import scrub_event_fields
from Src.Ingest.Fingerprint import compute_fingerprint
from Src.Storage.Queries import upsert_issue, insert_event

# ============================================================================
# String-based JSON helpers (shared patterns from envelope/otlp handlers)
# ============================================================================

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

# ============================================================================
# Response helpers
# ============================================================================

fn normalize_level(level_raw :: String) -> String do
  if level_raw == "" do "error" else level_raw end
end

fn normalize_environment(env_raw :: String) -> String do
  if env_raw == "" do "production" else env_raw end
end

# Truncate a string to a maximum length.
fn truncate_str(s :: String, max_len :: Int) -> String do
  if String.length(s) > max_len do
    String.slice(s, 0, max_len)
  else
    s
  end
end

fn build_generic_title(exception_type :: String, s_exception_value :: String, s_message :: String) -> String do
  let title_raw = if exception_type != "" && s_exception_value != "" do
    exception_type <> ": " <> s_exception_value
  else if exception_type != "" do
    exception_type
  else
    s_message
  end
  truncate_str(title_raw, 255)
end

fn store_generic_event(pool :: PoolHandle, project_id :: String, org_id :: String, message :: String, level :: String, environment :: String, release :: String, server_name :: String, exception_type :: String, exception_value :: String, stacktrace_json :: String, tags_json :: String, extra_json :: String) -> String!String do
  let event_id = Crypto.uuid4()
  let scrubbed = scrub_event_fields(pool, org_id, message, exception_value, stacktrace_json, tags_json, extra_json, "{}", server_name)?
  let s_message = Map.get(scrubbed, "message")
  let s_exception_value = Map.get(scrubbed, "exception_value")
  let s_stacktrace_json = Map.get(scrubbed, "stacktrace_json")
  let s_tags_json = Map.get(scrubbed, "tags_json")
  let s_extra_json = Map.get(scrubbed, "extra_json")
  let s_server_name = Map.get(scrubbed, "server_name")
  let fingerprint = compute_fingerprint(exception_type, s_stacktrace_json)
  let title = build_generic_title(exception_type, s_exception_value, s_message)
  let issue_row = upsert_issue(pool, project_id, fingerprint, title, level)?
  let issue_id = Map.get(issue_row, "id")
  let _ = insert_event(pool, project_id, issue_id, event_id, "now()", "generic", level, s_message, exception_type, s_exception_value, s_stacktrace_json, environment, release, s_server_name, s_tags_json, s_extra_json, "{}", "generic-api", "1.0", fingerprint)?
  Ok(event_id)
end

fn process_generic_event(pool :: PoolHandle, project_id :: String, org_id :: String, trimmed :: String) -> Response!String do
  if !String.starts_with(trimmed, "{") do
    Ok(HTTP.response(400, json { error: "invalid JSON" }))
  else
    let message = json_field(trimmed, "message")
    if message == "" do
      Ok(HTTP.response(400, json { error: "message is required" }))
    else
      let level = normalize_level(json_field(trimmed, "level"))
      let environment = normalize_environment(json_field(trimmed, "environment"))
      let release = json_field(trimmed, "release")
      let server_name = json_field(trimmed, "server_name")
      let exception_obj = extract_json_object(trimmed, "exception")
      let exception_type = json_field(exception_obj, "type")
      let exception_value = json_field(exception_obj, "value")
      let stacktrace_json = extract_json_array(exception_obj, "stacktrace")
      let tags_json = extract_json_object(trimmed, "tags")
      let extra_json = extract_json_object(trimmed, "extra")
      let event_id = store_generic_event(pool, project_id, org_id, message, level, environment, release, server_name, exception_type, exception_value, stacktrace_json, tags_json, extra_json)?
      Ok(HTTP.response(200, json { id: event_id }))
    end
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
  let preflight = validate_ingest_request(pool, request, 401, "", "generic", "invalid JSON")
  case preflight do
    Err(response) -> response
    Ok(ctx) -> do
      let project_id = Map.get(ctx, "project_id")
      let org_id = Map.get(ctx, "org_id")
      let trimmed = Map.get(ctx, "trimmed_body")
      let process_result = process_generic_event(pool, project_id, org_id, trimmed)
      case process_result do
        Ok(response) -> response
        Err(_) -> HTTP.response(500, json { error: "internal error" })
      end
    end
  end
end

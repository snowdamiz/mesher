# OTLP/HTTP JSON handler for error ingestion.
#
# Implements three OTLP endpoints:
#   POST /v1/logs   - Processes LogRecords with error severity
#   POST /v1/traces - Extracts exception span events
#   POST /v1/metrics - Stub (acknowledges, defers to Phase 4)
#
# OTLP spec: JSON encoding only (protobuf returns 415).
# User-approved scope decision: protobuf support deferred from Phase 2.
#
# All endpoints authenticate via Authorization Bearer header
# and return OTLP-spec JSON responses: {"partialSuccess":{}}
#
# Rate-limited responses use HTTP.response_with_headers with Retry-After header.
#
# All JSON parsing uses string-based extraction (no Json.stringify in Mesh).

from Src.Ingest.Auth import extract_and_validate_api_key
from Src.Ingest.Helpers import json_field
from Src.Ingest.Middleware import validate_ingest_request
from Src.Ingest.Scrubber import scrub_event_fields
from Src.Ingest.Fingerprint import compute_fingerprint
from Src.Storage.Queries import upsert_issue, insert_event

# ============================================================================
# String-based JSON helpers
# ============================================================================

# Extract a numeric field value as string from JSON.
# Handles both "field":123 and "field":"123" formats.
fn json_num_field(json_str :: String, field :: String) -> String do
  let quoted_search = "\"" <> field <> "\":\""
  if String.contains(json_str, quoted_search) do
    json_field(json_str, field)
  else
    let search = "\"" <> field <> "\":"
    if String.contains(json_str, search) do
      let parts = json_str |> String.split(search)
      if List.length(parts) >= 2 do
        let rest = List.last(parts)
        let comma_parts = rest |> String.split(",")
        let first = List.head(comma_parts)
        let brace_parts = first |> String.split("}")
        String.trim(List.head(brace_parts))
      else
        ""
      end
    else
      ""
    end
  end
end

# Extract a named OTLP attribute value.
# OTLP attributes: [{"key":"name","value":{"stringValue":"val"}}]
fn extract_attr_value(rest :: String, marker :: String) -> String do
  if String.contains(rest, marker) do
    let parts = rest |> String.split(marker)
    if List.length(parts) >= 2 do
      let value_tail = List.last(parts)
      let end_parts = String.split(value_tail, "\"")
      if List.length(end_parts) > 0 do List.head(end_parts) else "" end
    else
      ""
    end
  else
    ""
  end
end

fn extract_otlp_value(rest :: String) -> String do
  let string_value = extract_attr_value(rest, "\"stringValue\":\"")
  if string_value != "" do
    string_value
  else
    extract_attr_value(rest, "\"intValue\":\"")
  end
end

fn get_otlp_attr(attrs_str :: String, key :: String) -> String do
  let search = "\"key\":\"" <> key <> "\""
  if !String.contains(attrs_str, search) do
    ""
  else
    let parts = attrs_str |> String.split(search)
    if List.length(parts) >= 2 do
      extract_otlp_value(List.last(parts))
    else
      ""
    end
  end
end

# Extract the stringValue from a body object: "body":{"stringValue":"..."}
fn extract_body_string(json_str :: String) -> String do
  let search = "\"body\":{\"stringValue\":\""
  if String.contains(json_str, search) do
    let parts = json_str |> String.split(search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      let end_parts = rest |> String.split("\"")
      if List.length(end_parts) > 0 do
        List.head(end_parts)
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

# ============================================================================
# Stacktrace parsing
# ============================================================================

# Parse an OTLP plaintext stacktrace into JSON frames array.
# OTLP stacktrace: "Error\n    at func (file:line:col)\n    at ..."
# Returns JSON array string: [{"filename":"...","function":"...","in_app":true}]
fn parse_otlp_stacktrace(raw :: String) -> String do
  if raw == "" do
    "[]"
  else
    let lines = String.split(raw, "\\n")
    let at_lines = List.filter(lines, fn(line) do String.contains(line, " at ") end)
    build_frames(at_lines, 0, List.length(at_lines))
  end
end

# Build JSON frames from "at ..." lines using index-based iteration.
fn build_frames(lines :: List<String>, idx :: Int, len :: Int) -> String do
  if idx >= len do
    "[]"
  else
    let line = List.get(lines, idx)
    let frame = parse_at_line(line)
    let rest = build_frames(lines, idx + 1, len)
    if frame == "" do
      rest
    else if rest == "[]" do
      "[" <> frame <> "]"
    else
      let inner = String.slice(rest, 1, String.length(rest) - 1)
      "[" <> frame <> "," <> inner <> "]"
    end
  end
end

# Parse a single "at funcName (file:line:col)" line into a JSON frame.
fn parse_at_line(line :: String) -> String do
  let trimmed = line |> String.trim()
  if String.starts_with(trimmed, "at ") do
    let without_at = String.slice(trimmed, 3, String.length(trimmed))
    if String.contains(without_at, " (") do
      let paren_parts = without_at |> String.split(" (")
      let func_name = List.head(paren_parts)
      let file_part = List.last(paren_parts) |> String.replace(")", "")
      let colon_parts = file_part |> String.split(":")
      let filename = List.head(colon_parts)
      let in_app_str = if String.contains(filename, "node_modules/") do "false" else "true" end
      "{\"filename\":\"" <> filename <> "\",\"function\":\"" <> func_name <> "\",\"in_app\":" <> in_app_str <> "}"
    else
      let colon_parts = without_at |> String.split(":")
      let filename = List.head(colon_parts)
      let in_app_str = if String.contains(filename, "node_modules/") do "false" else "true" end
      "{\"filename\":\"" <> filename <> "\",\"function\":\"<anonymous>\",\"in_app\":" <> in_app_str <> "}"
    end
  else
    ""
  end
end

# ============================================================================
# Response helpers
# ============================================================================

# Check Content-Type header for protobuf.
fn is_protobuf_content(request) -> Bool do
  case Request.header(request, "content-type") do
    Some(ct) -> String.contains(ct, "application/x-protobuf")
    None -> false
  end
end

# ============================================================================
# Event processing pipeline
# ============================================================================

# Process a single extracted OTLP error event through scrub/fingerprint/store.
fn process_otlp_event(pool :: PoolHandle, project_id :: String, org_id :: String, exception_type :: String, exception_message :: String, raw_stacktrace :: String, message :: String, level :: String, environment :: String, server_name :: String, nano_timestamp :: String) -> String!String do
  let event_id = Crypto.uuid4()
  let stacktrace_json = parse_otlp_stacktrace(raw_stacktrace)

  # Scrub all fields
  let scrubbed = scrub_event_fields(pool, org_id, message, exception_message, stacktrace_json, "{}", "{}", "{}", server_name)?
  let s_message = scrubbed |> Map.get("message")
  let s_exception_value = scrubbed |> Map.get("exception_value")
  let s_stacktrace_json = scrubbed |> Map.get("stacktrace_json")
  let s_server_name = scrubbed |> Map.get("server_name")

  # Compute fingerprint
  let fingerprint = s_stacktrace_json |2> compute_fingerprint(exception_type)

  # Build title
  let title = if exception_type != "" do exception_type <> ": " <> s_message else s_message end

  # Upsert issue
  let issue_result_raw = fingerprint |3> upsert_issue(pool, project_id, title, level)
  let issue_result = issue_result_raw?
  let issue_id = issue_result |> Map.get("id")

  # Convert nano timestamp to timestamptz via SQL
  let ts_result = Repo.query_raw(pool, "SELECT to_timestamp($1::bigint / 1000000000.0)::text AS ts", [nano_timestamp])
  let timestamp = case ts_result do
    Ok(rows) -> if List.length(rows) > 0 do Map.get(List.head(rows), "ts") else "1970-01-01 00:00:00+00" end
    Err(_) -> "1970-01-01 00:00:00+00"
  end

  # Insert event
  insert_event(pool, project_id, issue_id, event_id, timestamp, "otlp", level, s_message, exception_type, s_exception_value, s_stacktrace_json, environment, "", s_server_name, "{}", "{}", "{}", "otlp", "1.0", fingerprint)
end

# ============================================================================
# OTLP Logs handler
# ============================================================================

# Check if a log record section contains error-level severity (>= 17).
fn is_error_severity(record :: String) -> Bool do
  String.contains(record, "\"severityNumber\":17") || String.contains(record, "\"severityNumber\":18") || String.contains(record, "\"severityNumber\":19") || String.contains(record, "\"severityNumber\":20") || String.contains(record, "\"severityNumber\":21") || String.contains(record, "\"severityNumber\":22") || String.contains(record, "\"severityNumber\":23") || String.contains(record, "\"severityNumber\":24")
end

# Check if a log record has fatal severity (>= 21).
fn is_fatal_severity(record :: String) -> Bool do
  String.contains(record, "\"severityNumber\":21") || String.contains(record, "\"severityNumber\":22") || String.contains(record, "\"severityNumber\":23") || String.contains(record, "\"severityNumber\":24")
end

# Process log records, iterating with index-based access.
fn process_log_records(pool :: PoolHandle, project_id :: String, org_id :: String, records :: List<String>, full_body :: String, idx :: Int, len :: Int) -> Int!String do
  if idx >= len do
    Ok(0)
  else
    let record = List.get(records, idx)
    let has_error = is_error_severity(record)
    if has_error do
      let level = if is_fatal_severity(record) do "fatal" else "error" end
      let exception_type = get_otlp_attr(record, "exception.type")
      let exception_message = get_otlp_attr(record, "exception.message")
      let raw_stacktrace = get_otlp_attr(record, "exception.stacktrace")
      let body_message = extract_body_string(record)
      let server_name = get_otlp_attr(full_body, "service.name")
      let environment = get_otlp_attr(full_body, "deployment.environment")
      let env = if environment == "" do "production" else environment end
      let nano_ts = json_num_field(record, "timeUnixNano")
      let msg = if exception_message != "" do exception_message else body_message end
      let _ = process_otlp_event(pool, project_id, org_id, exception_type, exception_message, raw_stacktrace, msg, level, env, server_name, nano_ts)?
      process_log_records(pool, project_id, org_id, records, full_body, idx + 1, len)
    else
      process_log_records(pool, project_id, org_id, records, full_body, idx + 1, len)
    end
  end
end

# ============================================================================
# OTLP Traces handler
# ============================================================================

# Process exception events from trace span sections.
fn process_trace_exceptions(pool :: PoolHandle, project_id :: String, org_id :: String, sections :: List<String>, full_body :: String, idx :: Int, len :: Int) -> Int!String do
  if idx >= len do
    Ok(0)
  else
    let section = List.get(sections, idx)
    let exception_type = get_otlp_attr(section, "exception.type")
    let exception_message = get_otlp_attr(section, "exception.message")
    let raw_stacktrace = get_otlp_attr(section, "exception.stacktrace")

    if exception_type != "" || exception_message != "" do
      let server_name = get_otlp_attr(full_body, "service.name")
      let environment = get_otlp_attr(full_body, "deployment.environment")
      let env = if environment == "" do "production" else environment end
      let nano_ts = json_num_field(section, "startTimeUnixNano")
      let ts = if nano_ts == "" do json_num_field(full_body, "startTimeUnixNano") else nano_ts end
      let msg = if exception_message != "" do exception_message else exception_type end
      let _ = process_otlp_event(pool, project_id, org_id, exception_type, exception_message, raw_stacktrace, msg, "error", env, server_name, ts)?
      process_trace_exceptions(pool, project_id, org_id, sections, full_body, idx + 1, len)
    else
      process_trace_exceptions(pool, project_id, org_id, sections, full_body, idx + 1, len)
    end
  end
end

fn process_otlp_mode(pool :: PoolHandle, project_id :: String, org_id :: String, raw_body :: String, mode :: String) -> Int!String do
  if mode == "logs" do
    let record_sections = raw_body |> String.split("\"logRecords\":[")
    let num_sections = List.length(record_sections)
    if num_sections >= 2 do
      let records_part = List.last(record_sections)
      let records = records_part |> String.split("},{")
      process_log_records(pool, project_id, org_id, records, raw_body, 0, List.length(records))
    else
      Ok(0)
    end
  else
    let exception_sections = raw_body |> String.split("\"name\":\"exception\"")
    let num_exceptions = List.length(exception_sections)
    if num_exceptions >= 2 do
      process_trace_exceptions(pool, project_id, org_id, exception_sections, raw_body, 1, num_exceptions)
    else
      Ok(0)
    end
  end
end

fn handle_otlp_mode(pool :: PoolHandle, request, mode :: String) -> Response do
  let is_pb = is_protobuf_content(request)
  if is_pb do
    HTTP.response(415, json { error: "protobuf not supported, use application/json" })
  else
    let preflight = validate_ingest_request(pool, request, 401, "", "otlp", "empty request body")
    case preflight do
      Err(response) -> response
      Ok(ctx) -> do
        let project_id = ctx |> Map.get("project_id")
        let org_id = ctx |> Map.get("org_id")
        let raw_body = ctx |> Map.get("body")
        let _ = raw_body |4> process_otlp_mode(pool, project_id, org_id, mode)
        HTTP.response(200, json { partialSuccess: %{} })
      end
    end
  end
end

# POST /v1/logs
#
# Accepts OTLP/HTTP JSON LogRecords with error severity and stores as events.
# Extracts exception.type, exception.message, exception.stacktrace from attributes.
# Returns OTLP-spec response: {"partialSuccess":{}}
pub fn handle_otlp_logs(pool :: PoolHandle, request) -> Response do
  handle_otlp_mode(pool, request, "logs")
end

# POST /v1/traces
#
# Accepts OTLP/HTTP JSON spans and extracts exception span events.
# Exception events have name == "exception" with attributes:
#   exception.type, exception.message, exception.stacktrace
# Returns OTLP-spec response: {"partialSuccess":{}}
pub fn handle_otlp_traces(pool :: PoolHandle, request) -> Response do
  handle_otlp_mode(pool, request, "traces")
end

# ============================================================================
# OTLP Metrics handler (stub)
# ============================================================================

# POST /v1/metrics
#
# INGEST-02: Accept and acknowledge metrics payloads.
# Metrics processing deferred to Phase 4.
# No rate limiting needed for stub (no storage cost).
pub fn handle_otlp_metrics(pool :: PoolHandle, request) -> Response do
  # 1. Content-Type check
  let is_pb = is_protobuf_content(request)
  if is_pb do
    HTTP.response(415, json { error: "protobuf not supported, use application/json" })
  else
    # 2. Auth
    let auth_result = extract_and_validate_api_key(pool, request)
    case auth_result do
      Err(msg) -> HTTP.response(401, json { error: msg })
      Ok(_) -> do
        println("[OTLP] Metrics received, deferred to Phase 4")
        HTTP.response(200, json { partialSuccess: %{} })
      end
    end
  end
end

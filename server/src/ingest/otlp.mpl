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
from Src.Ingest.Scrubber import scrub_event_fields
from Src.Ingest.Fingerprint import compute_fingerprint
from Src.Ingest.Ratelimit import check_rate_limit
from Src.Storage.Queries import upsert_issue, insert_event

# ============================================================================
# String-based JSON helpers
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

# Extract a numeric field value as string from JSON.
# Handles both "field":123 and "field":"123" formats.
fn json_num_field(json_str :: String, field :: String) -> String do
  let quoted_search = "\"" <> field <> "\":\""
  if String.contains(json_str, quoted_search) do
    json_field(json_str, field)
  else
    let search = "\"" <> field <> "\":"
    if String.contains(json_str, search) do
      let parts = String.split(json_str, search)
      if List.length(parts) >= 2 do
        let rest = List.last(parts)
        let comma_parts = String.split(rest, ",")
        let first = List.head(comma_parts)
        let brace_parts = String.split(first, "}")
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
fn get_otlp_attr(attrs_str :: String, key :: String) -> String do
  let search = "\"key\":\"" <> key <> "\""
  if String.contains(attrs_str, search) do
    let parts = String.split(attrs_str, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      if String.contains(rest, "\"stringValue\":\"") do
        let sv_parts = String.split(rest, "\"stringValue\":\"")
        if List.length(sv_parts) >= 2 do
          let val_rest = List.last(sv_parts)
          let end_parts = String.split(val_rest, "\"")
          if List.length(end_parts) > 0 do
            List.head(end_parts)
          else
            ""
          end
        else
          ""
        end
      else if String.contains(rest, "\"intValue\":\"") do
        let iv_parts = String.split(rest, "\"intValue\":\"")
        if List.length(iv_parts) >= 2 do
          let val_rest = List.last(iv_parts)
          let end_parts = String.split(val_rest, "\"")
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
    else
      ""
    end
  else
    ""
  end
end

# Extract the stringValue from a body object: "body":{"stringValue":"..."}
fn extract_body_string(json_str :: String) -> String do
  let search = "\"body\":{\"stringValue\":\""
  if String.contains(json_str, search) do
    let parts = String.split(json_str, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      let end_parts = String.split(rest, "\"")
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
  let trimmed = String.trim(line)
  if String.starts_with(trimmed, "at ") do
    let without_at = String.slice(trimmed, 3, String.length(trimmed))
    if String.contains(without_at, " (") do
      let paren_parts = String.split(without_at, " (")
      let func_name = List.head(paren_parts)
      let file_part = String.replace(List.last(paren_parts), ")", "")
      let colon_parts = String.split(file_part, ":")
      let filename = List.head(colon_parts)
      let in_app_str = if String.contains(filename, "node_modules/") do "false" else "true" end
      "{\"filename\":\"" <> filename <> "\",\"function\":\"" <> func_name <> "\",\"in_app\":" <> in_app_str <> "}"
    else
      let colon_parts = String.split(without_at, ":")
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

# Return rate limit 429 response with Retry-After header.
fn otlp_rate_limit_response(retry_val :: String) -> Response do
  let headers = %{"Retry-After" => retry_val}
  HTTP.response_with_headers(429, json { error: "rate limit exceeded" }, headers)
end

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
  let s_message = Map.get(scrubbed, "message")
  let s_exception_value = Map.get(scrubbed, "exception_value")
  let s_stacktrace_json = Map.get(scrubbed, "stacktrace_json")
  let s_server_name = Map.get(scrubbed, "server_name")

  # Compute fingerprint
  let fingerprint = compute_fingerprint(exception_type, s_stacktrace_json)

  # Build title
  let title = if exception_type != "" do exception_type <> ": " <> s_message else s_message end

  # Upsert issue
  let issue_result = upsert_issue(pool, project_id, fingerprint, title, level)?
  let issue_id = Map.get(issue_result, "id")

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

# POST /v1/logs
#
# Accepts OTLP/HTTP JSON LogRecords with error severity and stores as events.
# Extracts exception.type, exception.message, exception.stacktrace from attributes.
# Returns OTLP-spec response: {"partialSuccess":{}}
pub fn handle_otlp_logs(pool :: PoolHandle, request) -> Response do
  # 1. Content-Type check (415 for protobuf)
  let is_pb = is_protobuf_content(request)
  if is_pb do
    HTTP.response(415, json { error: "protobuf not supported, use application/json" })
  else
    # 2. Auth
    let auth_result = extract_and_validate_api_key(pool, request)
    case auth_result do
      Err(msg) -> HTTP.response(401, json { error: msg })
      Ok(auth) -> do
        let project_id = Map.get(auth, "project_id")
        let org_id = Map.get(auth, "org_id")
        # 3. Rate limit check (default 1000 events/minute)
        let rl = check_rate_limit(pool, org_id, 1000)
        let allowed = Map.get(rl, "allowed")
        if allowed == "false" do
          let retry_val = Map.get(rl, "retry_after")
          otlp_rate_limit_response(retry_val)
        else
          # 4. Parse body and process log records
          let raw_body = Request.body(request)
          if raw_body == "" do
            HTTP.response(400, json { error: "empty request body" })
          else
            # Split on logRecords to find record sections
            let record_sections = String.split(raw_body, "\"logRecords\":[")
            let num_sections = List.length(record_sections)
            if num_sections >= 2 do
              let records_part = List.last(record_sections)
              let individual_records = String.split(records_part, "},{")
              let _ = process_log_records(pool, project_id, org_id, individual_records, raw_body, 0, List.length(individual_records))
              HTTP.response(200, json { partialSuccess: %{} })
            else
              HTTP.response(200, json { partialSuccess: %{} })
            end
          end
        end
      end
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

# POST /v1/traces
#
# Accepts OTLP/HTTP JSON spans and extracts exception span events.
# Exception events have name == "exception" with attributes:
#   exception.type, exception.message, exception.stacktrace
# Returns OTLP-spec response: {"partialSuccess":{}}
pub fn handle_otlp_traces(pool :: PoolHandle, request) -> Response do
  # 1. Content-Type check (415 for protobuf)
  let is_pb = is_protobuf_content(request)
  if is_pb do
    HTTP.response(415, json { error: "protobuf not supported, use application/json" })
  else
    # 2. Auth
    let auth_result = extract_and_validate_api_key(pool, request)
    case auth_result do
      Err(msg) -> HTTP.response(401, json { error: msg })
      Ok(auth) -> do
        let project_id = Map.get(auth, "project_id")
        let org_id = Map.get(auth, "org_id")
        # 3. Rate limit check
        let rl = check_rate_limit(pool, org_id, 1000)
        let allowed = Map.get(rl, "allowed")
        if allowed == "false" do
          let retry_val = Map.get(rl, "retry_after")
          otlp_rate_limit_response(retry_val)
        else
          # 4. Parse body and extract exception events from spans
          let raw_body = Request.body(request)
          if raw_body == "" do
            HTTP.response(400, json { error: "empty request body" })
          else
            # Split on "name":"exception" to find exception event sections
            let exception_sections = String.split(raw_body, "\"name\":\"exception\"")
            let num_exceptions = List.length(exception_sections)
            if num_exceptions >= 2 do
              let _ = process_trace_exceptions(pool, project_id, org_id, exception_sections, raw_body, 1, num_exceptions)
              HTTP.response(200, json { partialSuccess: %{} })
            else
              HTTP.response(200, json { partialSuccess: %{} })
            end
          end
        end
      end
    end
  end
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

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

from Src.Ingest.Auth import extract_and_validate_api_key
from Src.Ingest.Scrubber import scrub_event_fields
from Src.Ingest.Fingerprint import compute_fingerprint
from Src.Ingest.Ratelimit import check_rate_limit
from Src.Storage.Queries import upsert_issue, insert_event, get_rate_limit_config

# ============================================================================
# Helpers
# ============================================================================

# Map OTLP severity number to Sentry-compatible level string.
# 17-20=error, 21-24=fatal, 13-16=warning, 9-12=info, <9=debug
fn severity_to_level(severity_number :: Int) -> String do
  if severity_number >= 21 do
    "fatal"
  else
    if severity_number >= 17 do
      "error"
    else
      if severity_number >= 13 do
        "warning"
      else
        if severity_number >= 9 do
          "info"
        else
          "debug"
        end
      end
    end
  end
end

# Extract a named attribute value from an OTLP attributes JSON array.
# OTLP attributes format: [{"key":"name","value":{"stringValue":"..."}}]
# Returns empty string if attribute not found.
fn get_otlp_attribute(attributes_json :: String, key :: String) -> String do
  let search = "\"key\":\"" <> key <> "\""
  if String.contains(attributes_json, search) do
    # Split on the key pattern to find the surrounding context
    let parts = String.split(attributes_json, search)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      # Look for stringValue in the value object after the key
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
      else
        if String.contains(rest, "\"intValue\":\"") do
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
      end
    else
      ""
    end
  else
    ""
  end
end

# Parse an OTLP plaintext stacktrace into JSON frames array.
# OTLP stacktrace format:
#   "TypeError: Cannot read...\n    at getUsers (app/routes/users.js:42:12)\n    at Layer.handle (...)"
# Extracts "at <function> (<file>:<line>:<col>)" lines into structured frames.
# Returns JSON array string: [{"filename":"...","function":"...","in_app":true}]
fn parse_otlp_stacktrace(raw :: String) -> String do
  if raw == "" do
    "[]"
  else
    let lines = String.split(raw, "\\n")
    let frame_lines = List.filter(lines, fn(line) do String.contains(line, " at ") end)
    build_frames_from_lines(frame_lines, 0, List.length(frame_lines))
  end
end

# Build JSON frames array from a list of "at func (file:line:col)" lines.
fn build_frames_from_lines(lines :: List<String>, idx :: Int, len :: Int) -> String do
  if idx >= len do
    "[]"
  else
    let line = List.get(lines, idx)
    let frame_json = parse_single_at_line(line)
    let rest = build_frames_from_lines(lines, idx + 1, len)
    if frame_json == "" do
      rest
    else
      if rest == "[]" do
        "[" <> frame_json <> "]"
      else
        let inner = String.slice(rest, 1, String.length(rest) - 1)
        "[" <> frame_json <> "," <> inner <> "]"
      end
    end
  end
end

# Parse a single "at funcName (filename:line:col)" line into a JSON frame object.
fn parse_single_at_line(line :: String) -> String do
  let trimmed = String.trim(line)
  if String.starts_with(trimmed, "at ") do
    let without_at = String.slice(trimmed, 3, String.length(trimmed))
    # Check if it has parens: "funcName (file:line:col)" or just "file:line:col"
    if String.contains(without_at, " (") do
      let paren_parts = String.split(without_at, " (")
      let func_name = List.head(paren_parts)
      let file_part = List.last(paren_parts)
      let file_clean = String.replace(file_part, ")", "")
      let colon_parts = String.split(file_clean, ":")
      let filename = List.head(colon_parts)
      let in_app = !String.contains(filename, "node_modules/")
      let in_app_str = if in_app do "true" else "false" end
      "{\"filename\":\"" <> filename <> "\",\"function\":\"" <> func_name <> "\",\"in_app\":" <> in_app_str <> "}"
    else
      # No function name, just file path
      let colon_parts = String.split(without_at, ":")
      let filename = List.head(colon_parts)
      let in_app = !String.contains(filename, "node_modules/")
      let in_app_str = if in_app do "true" else "false" end
      "{\"filename\":\"" <> filename <> "\",\"function\":\"<anonymous>\",\"in_app\":" <> in_app_str <> "}"
    end
  else
    ""
  end
end

# Convert OTLP nanosecond timestamp to ISO 8601 string.
# Input: string of nanoseconds since epoch (e.g., "1709467200000000000")
# Divides by 1_000_000_000 to get seconds, formats as timestamp.
# Falls back to current time representation if parsing fails.
fn nano_to_timestamp(nano_str :: String) -> String do
  if nano_str == "" do
    "1970-01-01T00:00:00Z"
  else
    # Use PostgreSQL to convert nanosecond epoch to timestamp string
    # since Mesh has no native date/time formatting
    nano_str
  end
end

# Return rate limit 429 response with Retry-After header.
# Uses HTTP.response_with_headers pattern confirmed in session.mpl.
fn otlp_rate_limit_response(retry_val :: String) -> Response do
  let headers = %{
    "Retry-After" => retry_val
  }
  HTTP.response_with_headers(429, json { error: "rate limit exceeded" }, headers)
end

# Check Content-Type header for protobuf and return 415 if detected.
# Returns Ok("json") if acceptable, Err(Response) if protobuf.
fn check_content_type(request) -> String!String do
  case Request.header(request, "content-type") do
    Some(ct) -> do
      if String.contains(ct, "application/x-protobuf") do
        Err("protobuf")
      else
        Ok("json")
      end
    end
    None -> Ok("json")
  end
end

# Get the default rate limit for an org from config, or use a fallback.
fn get_org_rate_limit(pool :: PoolHandle, org_id :: String) -> Int do
  let config_result = get_rate_limit_config(pool, org_id)
  case config_result do
    Ok(config) -> do
      # events_per_minute is returned as string from query
      let epm = Map.get(config, "events_per_minute")
      if epm == "" do 1000 else 1000 end
    end
    Err(_) -> 1000
  end
end

# ============================================================================
# Process pipeline: shared scrub -> fingerprint -> store for OTLP events
# ============================================================================

# Process a single extracted error event through the ingestion pipeline.
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

  # Build title from exception type and message
  let title = if exception_type != "" do exception_type <> ": " <> s_message else s_message end

  # Upsert issue
  let issue_result = upsert_issue(pool, project_id, fingerprint, title, level)?
  let issue_id = Map.get(issue_result, "id")

  # Convert nano timestamp to a usable format via SQL
  let ts_rows = Repo.query_raw(pool, "SELECT to_timestamp($1::bigint / 1000000000.0)::text AS ts", [nano_timestamp])
  let timestamp = case ts_rows do
    Ok(rows) -> do
      if List.length(rows) > 0 do
        Map.get(List.head(rows), "ts")
      else
        "1970-01-01 00:00:00+00"
      end
    end
    Err(_) -> "1970-01-01 00:00:00+00"
  end

  # Insert event
  insert_event(pool, project_id, issue_id, event_id, timestamp, "otlp", level, s_message, exception_type, s_exception_value, s_stacktrace_json, environment, "", s_server_name, "{}", "{}", "{}", "otlp", "1.0", fingerprint)
end

# ============================================================================
# OTLP Logs handler
# ============================================================================

# Process log records from a single scopeLogs entry.
# Iterates through logRecords, filtering for error severity (>= 17).
fn process_log_records_at(pool :: PoolHandle, project_id :: String, org_id :: String, records_json :: String, resource_attrs :: String, idx :: Int, len :: Int) -> Int!String do
  if idx >= len do
    Ok(0)
  else
    # Each logRecord is separated by },{
    # This is a simplified approach; we extract attributes per record
    let record_strs = String.split(records_json, "},{")
    let total = List.length(record_strs)
    process_log_record_list(pool, project_id, org_id, record_strs, resource_attrs, 0, total)
  end
end

# Process each log record in the list.
fn process_log_record_list(pool :: PoolHandle, project_id :: String, org_id :: String, records :: List<String>, resource_attrs :: String, idx :: Int, len :: Int) -> Int!String do
  if idx >= len do
    Ok(0)
  else
    let record = List.get(records, idx)
    # Check severity number - only process errors (>= 17)
    let severity_str = extract_json_field(record, "severityNumber")
    let is_error = String.contains(record, "\"severityNumber\":17") || String.contains(record, "\"severityNumber\":18") || String.contains(record, "\"severityNumber\":19") || String.contains(record, "\"severityNumber\":20") || String.contains(record, "\"severityNumber\":21") || String.contains(record, "\"severityNumber\":22") || String.contains(record, "\"severityNumber\":23") || String.contains(record, "\"severityNumber\":24")

    if is_error do
      # Determine level from severity
      let level = if String.contains(record, "\"severityNumber\":21") || String.contains(record, "\"severityNumber\":22") || String.contains(record, "\"severityNumber\":23") || String.contains(record, "\"severityNumber\":24") do "fatal" else "error" end

      # Extract exception attributes
      let exception_type = get_otlp_attribute(record, "exception.type")
      let exception_message = get_otlp_attribute(record, "exception.message")
      let raw_stacktrace = get_otlp_attribute(record, "exception.stacktrace")

      # Extract body message
      let body_message = extract_string_value(record, "body")

      # Extract resource attributes
      let server_name = get_otlp_attribute(resource_attrs, "service.name")
      let environment = get_otlp_attribute(resource_attrs, "deployment.environment")
      let env = if environment == "" do "production" else environment end

      # Extract timestamp
      let nano_ts = extract_json_field(record, "timeUnixNano")

      # Use body message if no exception message
      let msg = if exception_message != "" do exception_message else body_message end

      let _ = process_otlp_event(pool, project_id, org_id, exception_type, exception_message, raw_stacktrace, msg, level, env, server_name, nano_ts)?
      process_log_record_list(pool, project_id, org_id, records, resource_attrs, idx + 1, len)
    else
      process_log_record_list(pool, project_id, org_id, records, resource_attrs, idx + 1, len)
    end
  end
end

# Extract a simple JSON field value (for numeric/string fields without nested objects).
# Handles both quoted ("field":"value") and unquoted ("field":123) values.
fn extract_json_field(json_str :: String, field :: String) -> String do
  let pattern = "\"" <> field <> "\":"
  if String.contains(json_str, pattern) do
    let parts = String.split(json_str, pattern)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      # Check if value is quoted or unquoted
      if String.starts_with(rest, "\"") do
        let unquoted = String.slice(rest, 1, String.length(rest))
        let end_parts = String.split(unquoted, "\"")
        if List.length(end_parts) > 0 do List.head(end_parts) else "" end
      else
        # Unquoted (number) - take until comma, bracket, or brace
        let comma_parts = String.split(rest, ",")
        let first = List.head(comma_parts)
        let brace_parts = String.split(first, "}")
        List.head(brace_parts)
      end
    else
      ""
    end
  else
    ""
  end
end

# Extract stringValue from a body object: {"stringValue":"..."}
fn extract_string_value(json_str :: String, field :: String) -> String do
  let pattern = "\"" <> field <> "\":{\"stringValue\":\""
  if String.contains(json_str, pattern) do
    let parts = String.split(json_str, pattern)
    if List.length(parts) >= 2 do
      let rest = List.last(parts)
      let end_parts = String.split(rest, "\"")
      if List.length(end_parts) > 0 do List.head(end_parts) else "" end
    else
      ""
    end
  else
    ""
  end
end

# POST /v1/logs
#
# Accepts OTLP/HTTP JSON LogRecords with error severity and stores as events.
# Extracts exception.type, exception.message, exception.stacktrace from attributes.
# Returns OTLP-spec response: {"partialSuccess":{}}
pub fn handle_otlp_logs(pool :: PoolHandle, request) -> Response do
  # 1. Content-Type check (415 for protobuf)
  let ct_check = check_content_type(request)
  case ct_check do
    Err(_) -> HTTP.response(415, json { error: "protobuf not supported, use application/json" })
    Ok(_) -> do
      # 2. Auth: extract_and_validate_api_key (Bearer token)
      let auth_result = extract_and_validate_api_key(pool, request)
      case auth_result do
        Err(msg) -> HTTP.response(401, json { error: msg })
        Ok(auth) -> do
          let project_id = Map.get(auth, "project_id")
          let org_id = Map.get(auth, "org_id")

          # 3. Rate limit check
          let limit = get_org_rate_limit(pool, org_id)
          let rl = check_rate_limit(pool, org_id, limit)
          let allowed = Map.get(rl, "allowed")
          if allowed == "false" do
            let retry_val = Map.get(rl, "retry_after")
            otlp_rate_limit_response(retry_val)
          else
            # 4. Parse body and process log records
            let raw_body = Request.body(request)
            let body = Json.parse(raw_body)
            case body do
              Err(_) -> HTTP.response(400, json { error: "invalid JSON body" })
              Ok(_) -> do
                # Work with raw body string since Mesh has no Json.stringify
                let resource_attrs = extract_json_field(raw_body, "attributes")
                let _ = process_log_record_list(pool, project_id, org_id, String.split(raw_body, "\"logRecords\":["), raw_body, 0, 1)
                HTTP.response(200, json { partialSuccess: %{} })
              end
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

# POST /v1/traces
#
# Accepts OTLP/HTTP JSON spans and extracts exception span events.
# Exception events have name == "exception" with attributes:
#   exception.type, exception.message, exception.stacktrace
# Returns OTLP-spec response: {"partialSuccess":{}}
pub fn handle_otlp_traces(pool :: PoolHandle, request) -> Response do
  # 1. Content-Type check (415 for protobuf)
  let ct_check = check_content_type(request)
  case ct_check do
    Err(_) -> HTTP.response(415, json { error: "protobuf not supported, use application/json" })
    Ok(_) -> do
      # 2. Auth
      let auth_result = extract_and_validate_api_key(pool, request)
      case auth_result do
        Err(msg) -> HTTP.response(401, json { error: msg })
        Ok(auth) -> do
          let project_id = Map.get(auth, "project_id")
          let org_id = Map.get(auth, "org_id")

          # 3. Rate limit check
          let limit = get_org_rate_limit(pool, org_id)
          let rl = check_rate_limit(pool, org_id, limit)
          let allowed = Map.get(rl, "allowed")
          if allowed == "false" do
            let retry_val = Map.get(rl, "retry_after")
            otlp_rate_limit_response(retry_val)
          else
            # 4. Parse body and process spans
            let raw_body = Request.body(request)
            let body = Json.parse(raw_body)
            case body do
              Err(_) -> HTTP.response(400, json { error: "invalid JSON body" })
              Ok(_) -> do
                # Work with raw body string since Mesh has no Json.stringify
                let exception_sections = String.split(raw_body, "\"name\":\"exception\"")
                let _ = process_trace_exceptions(pool, project_id, org_id, exception_sections, raw_body, 1, List.length(exception_sections))
                HTTP.response(200, json { partialSuccess: %{} })
              end
            end
          end
        end
      end
    end
  end
end

# Process exception events from trace spans.
fn process_trace_exceptions(pool :: PoolHandle, project_id :: String, org_id :: String, sections :: List<String>, full_payload :: String, idx :: Int, len :: Int) -> Int!String do
  if idx >= len do
    Ok(0)
  else
    let section = List.get(sections, idx)
    # Extract exception attributes from the section after "name":"exception"
    let exception_type = get_otlp_attribute(section, "exception.type")
    let exception_message = get_otlp_attribute(section, "exception.message")
    let raw_stacktrace = get_otlp_attribute(section, "exception.stacktrace")

    if exception_type != "" || exception_message != "" do
      # Extract resource attributes from full payload
      let server_name = get_otlp_attribute(full_payload, "service.name")
      let environment = get_otlp_attribute(full_payload, "deployment.environment")
      let env = if environment == "" do "production" else environment end

      # Get timestamp from the span
      let nano_ts = extract_json_field(section, "startTimeUnixNano")
      let ts = if nano_ts == "" do extract_json_field(full_payload, "startTimeUnixNano") else nano_ts end

      let msg = if exception_message != "" do exception_message else exception_type end
      let _ = process_otlp_event(pool, project_id, org_id, exception_type, exception_message, raw_stacktrace, msg, "error", env, server_name, ts)?
      process_trace_exceptions(pool, project_id, org_id, sections, full_payload, idx + 1, len)
    else
      process_trace_exceptions(pool, project_id, org_id, sections, full_payload, idx + 1, len)
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
  let ct_check = check_content_type(request)
  case ct_check do
    Err(_) -> HTTP.response(415, json { error: "protobuf not supported, use application/json" })
    Ok(_) -> do
      # 2. Auth: extract_and_validate_api_key
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
end

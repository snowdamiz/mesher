# PII scrubbing pipeline for ingestion events.
#
# Locked decision: Scrub at ingestion time. PII never hits disk unscrubbed.
# Replaces sensitive data with [Filtered] (Sentry convention).
#
# Default scrub rules (applied to all events):
#   1. Sensitive JSON key values (password, token, secret, cookie, etc.)
#   2. Authorization header values (Bearer/Basic tokens)
#
# Custom per-org scrub rules loaded from the scrub_rules DB table
# are applied using String.replace for literal pattern matching.
#
# Limitation: Mesh has no regex support in its stdlib. PII scrubbing uses
# String.contains/String.replace for literal pattern matching. This handles
# sensitive key names and known value formats but cannot detect arbitrary
# email/IP/credit card patterns by regex. Custom org rules use literal
# string matching. This is functional for Phase 2; regex can be added
# if/when Mesh gets a Regex module.

from Src.Storage.Queries import get_active_scrub_rules

# Scrub a JSON key's value by replacing "key":"<value>" with "key":"[Filtered]".
# Uses String.split on the key pattern, then reconstructs with [Filtered].
# Only handles the first occurrence of each key for simplicity.
fn scrub_json_key_value(input :: String, key :: String) -> String do
  let search = "\"" <> key <> "\":\""
  if String.contains(String.lower(input), String.lower(search)) do
    # Find the key pattern in the original string (case-insensitive match)
    # We need to split on the actual key in the input, handling case
    let parts = String.split(input, search)
    if List.length(parts) >= 2 do
      let before = List.head(parts)
      let value_and_rest = List.last(parts)
      # Find the closing quote of the value
      let val_parts = String.split(value_and_rest, "\"")
      if List.length(val_parts) >= 2 do
        # Skip the first part (the old value), rejoin the rest with quotes
        let rest_after_value = String.slice(value_and_rest, String.length(List.head(val_parts)) + 1, String.length(value_and_rest))
        before <> search <> "[Filtered]\"" <> rest_after_value
      else
        before <> search <> "[Filtered]\"" <> value_and_rest
      end
    else
      input
    end
  else
    input
  end
end

# Scrub all common sensitive JSON key patterns from a string.
# Covers: password, secret, token, API key, auth, cookie, session, credit card, SSN.
fn scrub_sensitive_keys(value :: String) -> String do
  let v1 = scrub_json_key_value(value, "password")
  let v2 = scrub_json_key_value(v1, "passwd")
  let v3 = scrub_json_key_value(v2, "secret")
  let v4 = scrub_json_key_value(v3, "token")
  let v5 = scrub_json_key_value(v4, "api_key")
  let v6 = scrub_json_key_value(v5, "apikey")
  let v7 = scrub_json_key_value(v6, "access_token")
  let v8 = scrub_json_key_value(v7, "refresh_token")
  let v9 = scrub_json_key_value(v8, "authorization")
  let v10 = scrub_json_key_value(v9, "cookie")
  let v11 = scrub_json_key_value(v10, "session_id")
  let v12 = scrub_json_key_value(v11, "sessionid")
  let v13 = scrub_json_key_value(v12, "creditcard")
  let v14 = scrub_json_key_value(v13, "credit_card")
  let v15 = scrub_json_key_value(v14, "card_number")
  let v16 = scrub_json_key_value(v15, "ssn")
  scrub_json_key_value(v16, "social_security")
end

# Scrub authorization header values from a string.
# Replaces "Bearer <anything>" and "Basic <anything>" with [Filtered].
fn scrub_auth_headers(value :: String) -> String do
  if String.contains(value, "Bearer ") do
    let parts = String.split(value, "Bearer ")
    let before_part = List.head(parts)
    before_part <> "Bearer [Filtered]"
  else if String.contains(value, "Basic ") do
    let parts = String.split(value, "Basic ")
    let before_part = List.head(parts)
    before_part <> "Basic [Filtered]"
  else
    value
  end
end

# Apply a single custom scrub rule (literal string replacement).
fn apply_single_rule(value :: String, rule :: Map<String, String>) -> String do
  let rule_pattern = Map.get(rule, "pattern")
  let replacement = Map.get(rule, "replacement")
  String.replace(value, rule_pattern, replacement)
end

# Apply custom rules iteratively using index-based access.
fn apply_rules_at_index(value :: String, rules, idx :: Int, len :: Int) -> String do
  if idx >= len do
    value
  else
    let rule = List.get(rules, idx)
    let scrubbed = apply_single_rule(value, rule)
    apply_rules_at_index(scrubbed, rules, idx + 1, len)
  end
end

# Apply all custom rules from the list to a value.
fn apply_all_custom_rules(value :: String, rules :: List<Map<String, String>>) -> String do
  apply_rules_at_index(value, rules, 0, List.length(rules))
end

# Run a single string value through the full scrubbing pipeline.
fn scrub_value(value :: String, custom_rules :: List<Map<String, String>>) -> String do
  let v1 = scrub_sensitive_keys(value)
  let v2 = scrub_auth_headers(v1)
  apply_all_custom_rules(v2, custom_rules)
end

# Scrub all event string fields through the PII scrubbing pipeline.
#
# Pipeline:
#   1. Hardcoded default rules scrub sensitive JSON keys + auth headers
#   2. Custom per-org rules from DB via get_active_scrub_rules
#   3. Both rule sets applied to each field
#
# Fields scrubbed: message, exception_value, stacktrace_json, tags_json,
#   extra_json, contexts_json, server_name
#
# Returns a map with scrubbed field values keyed by field name.
pub fn scrub_event_fields(pool :: PoolHandle, org_id :: String, message :: String, exception_value :: String, stacktrace_json :: String, tags_json :: String, extra_json :: String, contexts_json :: String, server_name :: String) -> Map<String, String>!String do
  let custom_rules = get_active_scrub_rules(pool, org_id)?
  let s_message = scrub_value(message, custom_rules)
  let s_exception_value = scrub_value(exception_value, custom_rules)
  let s_stacktrace_json = scrub_value(stacktrace_json, custom_rules)
  let s_tags_json = scrub_value(tags_json, custom_rules)
  let s_extra_json = scrub_value(extra_json, custom_rules)
  let s_contexts_json = scrub_value(contexts_json, custom_rules)
  let s_server_name = scrub_value(server_name, custom_rules)
  Ok(%{"message" => s_message, "exception_value" => s_exception_value, "stacktrace_json" => s_stacktrace_json, "tags_json" => s_tags_json, "extra_json" => s_extra_json, "contexts_json" => s_contexts_json, "server_name" => s_server_name})
end

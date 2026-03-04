# API key authentication module for ingestion endpoints.
#
# Extracts and validates API keys for all ingestion protocols:
#   1. X-Sentry-Auth header (Sentry SDK format)
#   2. sentry_key query parameter (Sentry browser SDK format)
#   3. Authorization Bearer header (OTLP / generic API)
#
# All methods resolve to a raw API key string, which is SHA-256 hashed
# and validated against the api_keys table. On success, returns project_id
# and org_id for scoping all downstream operations.
#
# This module is separate from session-based auth (auth/session.mpl).
# Session auth protects the dashboard; API key auth protects ingestion.

from Src.Storage.Queries import validate_api_key_for_ingest

# Extract the value after "sentry_key=" from a single key=value pair string.
fn extract_key_value(pair :: String) -> String do
  let parts = String.split(pair, "=")
  if List.length(parts) >= 2 do
    List.last(parts)
  else
    ""
  end
end

# Parse the sentry_key value from an X-Sentry-Auth header.
# Header format: "Sentry sentry_key=<key>, sentry_version=7, sentry_client=sentry.javascript.node/9.x.x"
# Splits on ", " to get key=value pairs, filters for the one starting with "sentry_key=",
# then splits on "=" to extract the value.
fn parse_sentry_auth_header(header_value :: String) -> String!String do
  if String.starts_with(header_value, "Sentry ") do
    let without_prefix = String.replace(header_value, "Sentry ", "")
    let pairs = String.split(without_prefix, ", ")
    let matches = List.filter(pairs, fn(p) do String.starts_with(p, "sentry_key=") end)
    if List.length(matches) > 0 do
      let key_val = extract_key_value(List.head(matches))
      if key_val != "" do
        Ok(key_val)
      else
        Err("malformed sentry_key in X-Sentry-Auth header")
      end
    else
      Err("sentry_key not found in X-Sentry-Auth header")
    end
  else
    Err("invalid X-Sentry-Auth format")
  end
end

# Parse a Bearer token from an Authorization header.
# Format: "Bearer <api_key>"
fn parse_bearer_token(header_value :: String) -> String!String do
  if String.starts_with(header_value, "Bearer ") do
    let parts = String.split(header_value, " ")
    if List.length(parts) >= 2 do
      Ok(List.last(parts))
    else
      Err("malformed Authorization Bearer header")
    end
  else
    Err("unsupported Authorization scheme")
  end
end

# Try all three auth extraction methods in order. Returns the raw API key string.
#
# Method 1: X-Sentry-Auth header (Sentry SDK standard)
# Method 2: sentry_key query parameter (Sentry browser SDK)
# Method 3: Authorization Bearer header (OTLP / generic API)
#
# If none found: Err("no authentication provided")
pub fn extract_api_key(request) -> String!String do
  case Request.header(request, "x-sentry-auth") do
    Some(auth_header) -> parse_sentry_auth_header(auth_header)
    None -> do
      case Request.query(request, "sentry_key") do
        Some(key) -> Ok(key)
        None -> do
          case Request.header(request, "authorization") do
            Some(bearer) -> parse_bearer_token(bearer)
            None -> Err("no authentication provided")
          end
        end
      end
    end
  end
end

# Hash the raw API key and validate against the database.
# Returns a map with "project_id" and "org_id" keys on success.
pub fn validate_key(pool :: PoolHandle, raw_key :: String) -> Map<String, String>!String do
  let key_hash = Crypto.sha256(raw_key)
  validate_api_key_for_ingest(pool, key_hash)
end

# Convenience: extract + validate in one call. This is what handlers will use.
# Extracts the API key from the request using any supported method,
# hashes it with SHA-256, and validates against the api_keys table.
# Returns a map with "project_id", "org_id", and "project_name" keys.
pub fn extract_and_validate_api_key(pool :: PoolHandle, request) -> Map<String, String>!String do
  let raw_key = extract_api_key(request)?
  validate_key(pool, raw_key)
end

# Shared ingest request preflight middleware.
#
# Handles protocol-agnostic request validation in one place:
#   1. API key extraction + validation
#   2. Rate-limit check
#   3. Body extraction and empty-body guard
#
# Returns either:
#   Ok(%{"project_id","org_id","body","trimmed_body"})
#   Err(Response) ready to return from the handler

from Src.Ingest.Auth import extract_and_validate_api_key
from Src.Ingest.Ratelimit import check_rate_limit

fn get_auth_error_text(default_msg :: String, auth_msg :: String) -> String do
  if default_msg == "" do auth_msg else default_msg end
end

fn build_rate_limit_headers(protocol :: String, retry_val :: String) -> Map<String, String> do
  if protocol == "sentry" do
    %{"Retry-After" => retry_val, "X-Sentry-Rate-Limits" => retry_val <> ":error:scope"}
  else
    %{"Retry-After" => retry_val}
  end
end

fn build_rate_limit_response(protocol :: String, retry_val :: String) -> Response do
  let headers = build_rate_limit_headers(protocol, retry_val)
  if protocol == "sentry" do
    HTTP.response_with_headers(429, json { error: "rate limit exceeded", retry_after: retry_val }, headers)
  else
    HTTP.response_with_headers(429, json { error: "rate limit exceeded" }, headers)
  end
end

pub fn validate_ingest_request(pool :: PoolHandle, request, auth_status :: Int, auth_default_msg :: String, protocol :: String, empty_body_msg :: String) -> Map<String, String>!Response do
  let auth_result = extract_and_validate_api_key(pool, request)
  case auth_result do
    Err(auth_msg) -> do
      let error_text = get_auth_error_text(auth_default_msg, auth_msg)
      Err(HTTP.response(auth_status, json { error: error_text }))
    end
    Ok(auth) -> do
      let project_id = Map.get(auth, "project_id")
      let org_id = Map.get(auth, "org_id")
      let rl = check_rate_limit(pool, org_id, 1000)
      let allowed = Map.get(rl, "allowed")
      if allowed == "false" do
        let retry_val = Map.get(rl, "retry_after")
        Err(build_rate_limit_response(protocol, retry_val))
      else
        let body = Request.body(request)
        let trimmed = String.trim(body)
        if trimmed == "" do
          Err(HTTP.response(400, json { error: empty_body_msg }))
        else
          Ok(%{"project_id" => project_id, "org_id" => org_id, "body" => body, "trimmed_body" => trimmed})
        end
      end
    end
  end
end

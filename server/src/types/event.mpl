# Error ingestion type structs for the Mesher data layer.
# IngestEvent is the common internal representation for all ingestion protocols
# (Sentry envelope, OTLP, generic JSON) -- NOT a database-backed struct.
# Issue, RateLimitConfig, and ScrubRule are ORM-backed with deriving(Schema, Json, Row).

# Common internal event representation used in-memory for normalization before storage.
# All three ingestion protocols normalize into this struct before fingerprinting and persistence.
# Does NOT derive Schema or Row -- this struct is not mapped to a database table.
pub struct IngestEvent do
  event_id :: String
  project_id :: String
  org_id :: String
  timestamp :: String
  platform :: String
  level :: String
  message :: String
  exception_type :: String
  exception_value :: String
  stacktrace_json :: String
  environment :: String
  release_tag :: String
  server_name :: String
  tags_json :: String
  extra_json :: String
  contexts_json :: String
  sdk_name :: String
  sdk_version :: String
end deriving(Json)

# Issue model -- deduplicated error groups identified by fingerprint.
# Status lifecycle: open -> resolved/ignored, with auto-reopen on new event via upsert.
pub struct Issue do
  table "issues"
  id :: String
  project_id :: String
  fingerprint :: String
  title :: String
  level :: String
  status :: String
  first_seen :: String
  last_seen :: String
  event_count :: String
  environment :: Option<String>
  metadata_json :: String
  created_at :: String
end deriving(Schema, Json, Row)

# Per-org rate limiting configuration.
# Default limits applied if no config row exists for an org.
pub struct RateLimitConfig do
  table "rate_limit_configs"
  id :: String
  org_id :: String
  events_per_minute :: String
  burst_limit :: String
  created_at :: String
  updated_at :: String
end deriving(Schema, Json, Row)

# Per-org PII scrubbing rule with regex pattern.
# Active rules are applied at ingestion time before fingerprinting and persistence.
pub struct ScrubRule do
  table "scrub_rules"
  id :: String
  org_id :: String
  pattern :: String
  replacement :: String
  description :: Option<String>
  is_active :: String
  created_at :: String
end deriving(Schema, Json, Row)

# Migration: Create error ingestion tables (issues, events, rate_limit_configs, scrub_rules).
# Tables created in FK dependency order. Events table is converted to a TimescaleDB hypertable.
# Issues uses Pool.execute for composite UNIQUE(project_id, fingerprint) constraint.
# Events uses Pool.execute because we need hypertable conversion immediately after creation.

pub fn up(pool :: PoolHandle) -> Int!String do
  # Enable TimescaleDB extension for hypertable support
  Pool.execute(pool, "CREATE EXTENSION IF NOT EXISTS timescaledb", [])?

  # 1. issues table (no FK to events -- events FK to issues)
  # Uses Pool.execute for composite UNIQUE constraint (same pattern as org_memberships)
  Pool.execute(pool, "CREATE TABLE issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    fingerprint TEXT NOT NULL,
    title TEXT NOT NULL,
    level TEXT NOT NULL DEFAULT 'error',
    status TEXT NOT NULL DEFAULT 'open',
    first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_count INT NOT NULL DEFAULT 1,
    environment TEXT,
    metadata_json TEXT DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(project_id, fingerprint)
  )", [])?

  # Issues indexes
  Pool.execute(pool, "CREATE INDEX idx_issues_project_status ON issues (project_id, status)", [])?
  Pool.execute(pool, "CREATE INDEX idx_issues_project_last_seen ON issues (project_id, last_seen DESC)", [])?
  Pool.execute(pool, "CREATE INDEX idx_issues_fingerprint ON issues (project_id, fingerprint)", [])?

  # 2. events table (FK to projects and issues)
  # Uses Pool.execute because we need hypertable conversion immediately after.
  # No PRIMARY KEY on id -- TimescaleDB hypertables require the partitioning column (timestamp)
  # to be part of any unique index. id is still generated, just not a PK constraint.
  Pool.execute(pool, "CREATE TABLE events (
    id UUID DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    issue_id UUID NOT NULL REFERENCES issues(id),
    event_id TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    platform TEXT NOT NULL DEFAULT 'unknown',
    level TEXT NOT NULL DEFAULT 'error',
    message TEXT,
    exception_type TEXT,
    exception_value TEXT,
    stacktrace_json TEXT,
    environment TEXT NOT NULL DEFAULT 'production',
    release_tag TEXT,
    server_name TEXT,
    tags_json TEXT DEFAULT '{}',
    extra_json TEXT DEFAULT '{}',
    contexts_json TEXT DEFAULT '{}',
    sdk_name TEXT,
    sdk_version TEXT,
    fingerprint TEXT NOT NULL
  )", [])?

  # Convert events to TimescaleDB hypertable for time-series performance
  Pool.execute(pool, "SELECT create_hypertable('events', 'timestamp')", [])?

  # Events indexes
  Pool.execute(pool, "CREATE INDEX idx_events_project_ts ON events (project_id, timestamp DESC)", [])?
  Pool.execute(pool, "CREATE INDEX idx_events_issue ON events (issue_id, timestamp DESC)", [])?
  Pool.execute(pool, "CREATE INDEX idx_events_fingerprint ON events (fingerprint)", [])?
  Pool.execute(pool, "CREATE INDEX idx_events_environment ON events (project_id, environment)", [])?
  Pool.execute(pool, "CREATE INDEX idx_events_level ON events (project_id, level)", [])?

  # 3. rate_limit_configs table (per-org rate limiting configuration)
  Migration.create_table(pool, "rate_limit_configs", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "org_id:UUID:NOT NULL REFERENCES organizations(id) ON DELETE CASCADE UNIQUE",
    "events_per_minute:INT:NOT NULL DEFAULT 1000",
    "burst_limit:INT:NOT NULL DEFAULT 100",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()",
    "updated_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # 4. scrub_rules table (per-org PII scrubbing patterns)
  Migration.create_table(pool, "scrub_rules", [
    "id:UUID:PRIMARY KEY DEFAULT gen_random_uuid()",
    "org_id:UUID:NOT NULL REFERENCES organizations(id) ON DELETE CASCADE",
    "pattern:TEXT:NOT NULL",
    "replacement:TEXT:NOT NULL DEFAULT '[Filtered]'",
    "description:TEXT",
    "is_active:BOOLEAN:NOT NULL DEFAULT true",
    "created_at:TIMESTAMPTZ:NOT NULL DEFAULT now()"
  ])?

  # Scrub rules partial index (only active rules, filtered by org)
  Pool.execute(pool, "CREATE INDEX idx_scrub_rules_org ON scrub_rules (org_id) WHERE is_active = true", [])?

  Ok(0)
end

pub fn down(pool :: PoolHandle) -> Int!String do
  # Drop in reverse FK dependency order
  Migration.drop_table(pool, "scrub_rules")?
  Migration.drop_table(pool, "rate_limit_configs")?
  Migration.drop_table(pool, "events")?
  Migration.drop_table(pool, "issues")?
  Ok(0)
end

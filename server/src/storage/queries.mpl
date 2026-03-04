# Centralized query helper functions for all Mesher entity types.
# Provides CRUD operations using ORM Repo/Query calls for all data access.
# All functions take pool :: PoolHandle as first argument and return Result types.
# crypt()/gen_salt() uses two-step pattern (query_raw then ORM insert/update).
# NOW() updates use two-step pattern (query_raw for timestamp, then ORM update_where).
# UUID columns use ::uuid casts in where_raw clauses.

from Src.Types.User import User, OrgMembership, Session, Invite, PasswordResetToken
from Src.Types.Project import Organization, Project, ApiKey
from Src.Types.Event import Issue, RateLimitConfig, ScrubRule

# ============================================================================
# User functions
# ============================================================================

# Create a new user with bcrypt password hashing via pgcrypto (cost factor 12).
# Two-step pattern: Repo.query_raw for crypt() hash generation, then Repo.insert.
pub fn create_user(pool :: PoolHandle, email :: String, password :: String) -> String!String do
  # Step 1: Hash password via pgcrypto
  let hash_rows = Repo.query_raw(pool, "SELECT crypt($1, gen_salt('bf', 12)) AS hash", [password])?
  if List.length(hash_rows) > 0 do
    let password_hash = Map.get(List.head(hash_rows), "hash")
    # Step 2: Insert user with ORM
    let fields = %{"email" => email, "password_hash" => password_hash}
    let row = Repo.insert(pool, User.__table__(), fields)?
    Ok(Map.get(row, "id"))
  else
    Err("create_user: password hashing failed")
  end
end

# Authenticate a user by email and password.
# Returns the user row if credentials match, Err("not found") otherwise.
# Uses ORM Query.where + Query.where_raw for crypt() password verification.
pub fn authenticate_user(pool :: PoolHandle, email :: String, password :: String) -> Map<String, String>!String do
  let q = Query.from(User.__table__())
    |> Query.where(:email, email)
    |> Query.where_raw("password_hash = crypt(?, password_hash)", [password])
    |> Query.select_raw(["id::text", "email"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# Get a user by email address.
# Returns the user row or Err("not found").
pub fn get_user_by_email(pool :: PoolHandle, email :: String) -> Map<String, String>!String do
  let q = Query.from(User.__table__())
    |> Query.where(:email, email)
    |> Query.select_raw(["id::text", "email"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# Update a user's password.
# Two-step pattern: Repo.query_raw for crypt() hash, then Repo.update_where.
pub fn update_user_password(pool :: PoolHandle, user_id :: String, new_password :: String) -> Int!String do
  # Step 1: Hash new password via pgcrypto
  let hash_rows = Repo.query_raw(pool, "SELECT crypt($1, gen_salt('bf', 12)) AS hash", [new_password])?
  if List.length(hash_rows) > 0 do
    let password_hash = Map.get(List.head(hash_rows), "hash")
    # Step 2: Update with ORM
    let q = Query.from(User.__table__())
      |> Query.where_raw("id = ?::uuid", [user_id])
    let _ = Repo.update_where(pool, User.__table__(), %{"password_hash" => password_hash}, q)?
    Ok(1)
  else
    Err("update_user_password: password hashing failed")
  end
end

# ============================================================================
# Session functions
# ============================================================================

# Create a new session with a cryptographically random token.
# Returns the 64-char hex token (two UUID4s with hyphens stripped).
pub fn create_session(pool :: PoolHandle, user_id :: String) -> String!String do
  let uuid1 = Crypto.uuid4() |> String.replace("-", "")
  let uuid2 = Crypto.uuid4() |> String.replace("-", "")
  let token = uuid1 <> uuid2
  let fields = %{"token" => token, "user_id" => user_id}
  let _ = Repo.insert(pool, Session.__table__(), fields)?
  Ok(token)
end

# Validate a session token. Returns the session row if valid and not expired.
# Uses ORM Query.where + Query.where_raw for expiry check.
pub fn validate_session(pool :: PoolHandle, token :: String) -> Map<String, String>!String do
  let q = Query.from(Session.__table__())
    |> Query.where(:token, token)
    |> Query.where_raw("expires_at > now()", [])
    |> Query.select_raw(["token", "user_id::text"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# Delete a session by token (logout).
# Uses ORM Repo.delete_where -- zero raw SQL.
pub fn delete_session(pool :: PoolHandle, token :: String) -> Int!String do
  let q = Query.from(Session.__table__())
    |> Query.where(:token, token)
  Repo.delete_where(pool, Session.__table__(), q)
end

# Delete all sessions for a user (e.g., after password change).
pub fn delete_user_sessions(pool :: PoolHandle, user_id :: String) -> Int!String do
  let q = Query.from(Session.__table__())
    |> Query.where_raw("user_id = ?::uuid", [user_id])
  Repo.delete_where(pool, Session.__table__(), q)
end

# Clean up expired sessions. Returns number of deleted rows.
pub fn cleanup_expired_sessions(pool :: PoolHandle) -> Int!String do
  let q = Query.from(Session.__table__())
    |> Query.where_raw("expires_at < now()", [])
  Repo.delete_where(pool, Session.__table__(), q)
end

# ============================================================================
# Organization functions
# ============================================================================

# Insert a new organization. Returns the generated UUID.
pub fn insert_org(pool :: PoolHandle, name :: String, slug :: String) -> String!String do
  let fields = %{"name" => name, "slug" => slug}
  let row = Repo.insert(pool, Organization.__table__(), fields)?
  Ok(Map.get(row, "id"))
end

# Get an organization by ID.
pub fn get_org(pool :: PoolHandle, id :: String) -> Map<String, String>!String do
  let q = Query.from(Organization.__table__())
    |> Query.where_raw("id = ?::uuid", [id])
    |> Query.select_raw(["id::text", "name", "slug", "created_at::text"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# List all organizations a user belongs to, with role.
# Uses JOIN between organizations and org_memberships.
pub fn list_user_orgs(pool :: PoolHandle, user_id :: String) -> List<Map<String, String>>!String do
  let q = Query.from(Organization.__table__())
    |> Query.join_as(:inner, OrgMembership.__table__(), "m", "m.org_id = organizations.id")
    |> Query.where_raw("m.user_id = ?::uuid", [user_id])
    |> Query.select_raw(["organizations.id::text", "organizations.name", "organizations.slug", "organizations.created_at::text", "m.role"])
    |> Query.order_by_raw("organizations.created_at")
  Repo.all(pool, q)
end

# ============================================================================
# Membership functions
# ============================================================================

# Add a user to an organization with a role (owner/admin/member).
pub fn add_member(pool :: PoolHandle, org_id :: String, user_id :: String, role :: String) -> String!String do
  let fields = %{"org_id" => org_id, "user_id" => user_id, "role" => role}
  let row = Repo.insert(pool, OrgMembership.__table__(), fields)?
  Ok(Map.get(row, "id"))
end

# Check if a user is a member of an organization. Returns membership row or Err.
pub fn check_membership(pool :: PoolHandle, org_id :: String, user_id :: String) -> Map<String, String>!String do
  let q = Query.from(OrgMembership.__table__())
    |> Query.where_raw("org_id = ?::uuid AND user_id = ?::uuid", [org_id, user_id])
    |> Query.select_raw(["id::text", "role"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not a member")
  end
end

# ============================================================================
# Invite functions
# ============================================================================

# Create an invite for a user to join an organization.
# Two-step: get expires_at timestamp via query_raw, then Repo.insert.
pub fn create_invite(pool :: PoolHandle, org_id :: String, email :: String, token :: String, invited_by :: String) -> String!String do
  # Step 1: Get expiry timestamp (now + 7 days)
  let ts_rows = Repo.query_raw(pool, "SELECT (now() + interval '7 days')::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let expires_at = Map.get(List.head(ts_rows), "ts")
    # Step 2: Insert with ORM
    let fields = %{"org_id" => org_id, "email" => email, "token" => token, "invited_by" => invited_by, "expires_at" => expires_at}
    let row = Repo.insert(pool, Invite.__table__(), fields)?
    Ok(Map.get(row, "id"))
  else
    Err("create_invite: timestamp generation failed")
  end
end

# Get a pending (not accepted, not revoked, not expired) invite by token.
pub fn get_pending_invite(pool :: PoolHandle, token :: String) -> Map<String, String>!String do
  let q = Query.from(Invite.__table__())
    |> Query.where(:token, token)
    |> Query.where_raw("accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()", [])
    |> Query.select_raw(["id::text", "org_id::text", "email"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# Check if a pending invite already exists for an email in an org.
pub fn check_pending_invite_by_email(pool :: PoolHandle, org_id :: String, email :: String) -> Bool!String do
  let q = Query.from(Invite.__table__())
    |> Query.where_raw("org_id = ?::uuid", [org_id])
    |> Query.where(:email, email)
    |> Query.where_raw("accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()", [])
    |> Query.select_raw(["1 AS found"])
  let rows = Repo.all(pool, q)?
  Ok(List.length(rows) > 0)
end

# Check if a user with the given email is already a member of the org.
# Uses JOIN between org_memberships and users.
pub fn check_existing_member_by_email(pool :: PoolHandle, org_id :: String, email :: String) -> Bool!String do
  let q = Query.from(OrgMembership.__table__())
    |> Query.join_as(:inner, User.__table__(), "u", "u.id = org_memberships.user_id")
    |> Query.where_raw("org_memberships.org_id = ?::uuid", [org_id])
    |> Query.where_raw("u.email = ?", [email])
    |> Query.select_raw(["1 AS found"])
  let rows = Repo.all(pool, q)?
  Ok(List.length(rows) > 0)
end

# Accept an invite by setting accepted_at.
# Two-step: get now() timestamp, then Repo.update_where.
pub fn accept_invite(pool :: PoolHandle, invite_id :: String) -> Int!String do
  let ts_rows = Repo.query_raw(pool, "SELECT now()::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let ts = Map.get(List.head(ts_rows), "ts")
    let q = Query.from(Invite.__table__())
      |> Query.where_raw("id = ?::uuid", [invite_id])
    let _ = Repo.update_where(pool, Invite.__table__(), %{"accepted_at" => ts}, q)?
    Ok(1)
  else
    Err("accept_invite: timestamp generation failed")
  end
end

# Revoke an invite by setting revoked_at.
# Two-step: get now() timestamp, then Repo.update_where.
pub fn revoke_invite(pool :: PoolHandle, invite_id :: String, org_id :: String) -> Int!String do
  let ts_rows = Repo.query_raw(pool, "SELECT now()::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let ts = Map.get(List.head(ts_rows), "ts")
    let q = Query.from(Invite.__table__())
      |> Query.where_raw("id = ?::uuid AND org_id = ?::uuid AND revoked_at IS NULL", [invite_id, org_id])
    let _ = Repo.update_where(pool, Invite.__table__(), %{"revoked_at" => ts}, q)?
    Ok(1)
  else
    Err("revoke_invite: timestamp generation failed")
  end
end

# List all invites for an organization, ordered by created_at DESC.
pub fn list_invites(pool :: PoolHandle, org_id :: String) -> List<Map<String, String>>!String do
  let q = Query.from(Invite.__table__())
    |> Query.where_raw("org_id = ?::uuid", [org_id])
    |> Query.select_raw(["id::text", "org_id::text", "email", "token", "invited_by::text", "expires_at::text", "COALESCE(accepted_at::text, '') AS accepted_at", "COALESCE(revoked_at::text, '') AS revoked_at", "created_at::text"])
    |> Query.order_by_raw("created_at DESC")
  Repo.all(pool, q)
end

# ============================================================================
# Password Reset functions
# ============================================================================

# Invalidate existing unused reset tokens for a user.
# Two-step: get now() timestamp, then Repo.update_where.
pub fn invalidate_existing_reset_tokens(pool :: PoolHandle, user_id :: String) -> Int!String do
  let ts_rows = Repo.query_raw(pool, "SELECT now()::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let ts = Map.get(List.head(ts_rows), "ts")
    let q = Query.from(PasswordResetToken.__table__())
      |> Query.where_raw("user_id = ?::uuid AND used_at IS NULL", [user_id])
    let _ = Repo.update_where(pool, PasswordResetToken.__table__(), %{"used_at" => ts}, q)?
    Ok(1)
  else
    Err("invalidate_existing_reset_tokens: timestamp generation failed")
  end
end

# Create a new password reset token.
# Two-step: get expires_at timestamp (now + 1 hour), then Repo.insert.
pub fn create_reset_token(pool :: PoolHandle, user_id :: String, token_hash :: String) -> String!String do
  let ts_rows = Repo.query_raw(pool, "SELECT (now() + interval '1 hour')::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let expires_at = Map.get(List.head(ts_rows), "ts")
    let fields = %{"user_id" => user_id, "token_hash" => token_hash, "expires_at" => expires_at}
    let row = Repo.insert(pool, PasswordResetToken.__table__(), fields)?
    Ok(Map.get(row, "id"))
  else
    Err("create_reset_token: timestamp generation failed")
  end
end

# Validate a reset token by hash. Returns the token row if valid and unused.
pub fn validate_reset_token(pool :: PoolHandle, token_hash :: String) -> Map<String, String>!String do
  let q = Query.from(PasswordResetToken.__table__())
    |> Query.where(:token_hash, token_hash)
    |> Query.where_raw("expires_at > now() AND used_at IS NULL", [])
    |> Query.select_raw(["id::text", "user_id::text"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# Mark a reset token as used.
# Two-step: get now() timestamp, then Repo.update_where.
pub fn mark_reset_token_used(pool :: PoolHandle, token_id :: String) -> Int!String do
  let ts_rows = Repo.query_raw(pool, "SELECT now()::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let ts = Map.get(List.head(ts_rows), "ts")
    let q = Query.from(PasswordResetToken.__table__())
      |> Query.where_raw("id = ?::uuid", [token_id])
    let _ = Repo.update_where(pool, PasswordResetToken.__table__(), %{"used_at" => ts}, q)?
    Ok(1)
  else
    Err("mark_reset_token_used: timestamp generation failed")
  end
end

# ============================================================================
# Project functions
# ============================================================================

# Create a new project. Returns the generated UUID.
pub fn create_project(pool :: PoolHandle, org_id :: String, name :: String) -> String!String do
  let fields = %{"org_id" => org_id, "name" => name}
  let row = Repo.insert(pool, Project.__table__(), fields)?
  Ok(Map.get(row, "id"))
end

# List all projects for an organization, ordered by created_at.
pub fn list_projects(pool :: PoolHandle, org_id :: String) -> List<Map<String, String>>!String do
  let q = Query.from(Project.__table__())
    |> Query.where_raw("org_id = ?::uuid", [org_id])
    |> Query.select_raw(["id::text", "org_id::text", "name", "created_at::text"])
    |> Query.order_by_raw("created_at")
  Repo.all(pool, q)
end

# ============================================================================
# API Key functions
# ============================================================================

# Create a new API key for a project. Returns the generated UUID.
pub fn create_api_key(pool :: PoolHandle, project_id :: String, key_hash :: String, key_prefix :: String, label :: String) -> String!String do
  let fields = %{"project_id" => project_id, "key_hash" => key_hash, "key_prefix" => key_prefix, "label" => label}
  let row = Repo.insert(pool, ApiKey.__table__(), fields)?
  Ok(Map.get(row, "id"))
end

# List all API keys for a project, ordered by created_at DESC.
pub fn list_api_keys(pool :: PoolHandle, project_id :: String) -> List<Map<String, String>>!String do
  let q = Query.from(ApiKey.__table__())
    |> Query.where_raw("project_id = ?::uuid", [project_id])
    |> Query.select_raw(["id::text", "project_id::text", "key_hash", "key_prefix", "label", "created_at::text", "COALESCE(revoked_at::text, '') AS revoked_at"])
    |> Query.order_by_raw("created_at DESC")
  Repo.all(pool, q)
end

# Revoke an API key by setting revoked_at to now().
# Two-step pattern: Repo.query_raw for now() timestamp, then Repo.update_where.
pub fn revoke_api_key(pool :: PoolHandle, key_id :: String) -> Int!String do
  let ts_rows = Repo.query_raw(pool, "SELECT now()::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let ts = Map.get(List.head(ts_rows), "ts")
    let q = Query.from(ApiKey.__table__())
      |> Query.where_raw("id = ?::uuid AND revoked_at IS NULL", [key_id])
    let _ = Repo.update_where(pool, ApiKey.__table__(), %{"revoked_at" => ts}, q)?
    Ok(1)
  else
    Err("revoke_api_key: timestamp generation failed")
  end
end

# ============================================================================
# OAuth-specific functions
# ============================================================================

# Store an OAuth state token as a session row with short expiry.
# Uses a placeholder user_id (all zeros UUID) since OAuth state is transient.
pub fn store_oauth_state(pool :: PoolHandle, state :: String) -> Int!String do
  let ts_rows = Repo.query_raw(pool, "SELECT (now() + interval '10 minutes')::text AS ts", [])?
  if List.length(ts_rows) > 0 do
    let expires_at = Map.get(List.head(ts_rows), "ts")
    let token = "oauth_state_" <> state
    let fields = %{"token" => token, "user_id" => "00000000-0000-0000-0000-000000000000", "expires_at" => expires_at}
    let _ = Repo.insert(pool, Session.__table__(), fields)?
    Ok(1)
  else
    Err("store_oauth_state: timestamp generation failed")
  end
end

# Validate an OAuth state token. Returns true if valid and not expired.
pub fn validate_oauth_state(pool :: PoolHandle, state :: String) -> Bool!String do
  let token = "oauth_state_" <> state
  let q = Query.from(Session.__table__())
    |> Query.where(:token, token)
    |> Query.where_raw("expires_at > now()", [])
    |> Query.select_raw(["1 AS found"])
  let rows = Repo.all(pool, q)?
  Ok(List.length(rows) > 0)
end

# Delete an OAuth state token after use.
pub fn delete_oauth_state(pool :: PoolHandle, state :: String) -> Int!String do
  let token = "oauth_state_" <> state
  let q = Query.from(Session.__table__())
    |> Query.where(:token, token)
  Repo.delete_where(pool, Session.__table__(), q)
end

# Upsert an OAuth user: find by email or create with random password.
# Returns the user ID.
pub fn upsert_oauth_user(pool :: PoolHandle, email :: String) -> String!String do
  # Check if user exists
  let q = Query.from(User.__table__())
    |> Query.where(:email, email)
    |> Query.select_raw(["id::text"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(Map.get(List.head(rows), "id"))
  else
    # Create new user with random password (crypt of uuid4)
    let random_pw = Crypto.uuid4()
    let hash_rows = Repo.query_raw(pool, "SELECT crypt($1, gen_salt('bf', 12)) AS hash", [random_pw])?
    if List.length(hash_rows) > 0 do
      let password_hash = Map.get(List.head(hash_rows), "hash")
      let fields = %{"email" => email, "password_hash" => password_hash}
      let row = Repo.insert(pool, User.__table__(), fields)?
      Ok(Map.get(row, "id"))
    else
      Err("upsert_oauth_user: password hashing failed")
    end
  end
end

# ============================================================================
# Ingestion query functions
# ============================================================================

# Upsert an issue by fingerprint. Creates a new issue or updates an existing one.
# On conflict (same project_id + fingerprint): increments event_count, updates last_seen,
# and resets status from resolved/ignored to open (regression detection).
# Returns the issue id and current status.
pub fn upsert_issue(pool :: PoolHandle, project_id :: String, fingerprint :: String, title :: String, level :: String) -> Map<String, String>!String do
  let rows = Repo.query_raw(pool, "INSERT INTO issues (id, project_id, fingerprint, title, level, first_seen, last_seen, event_count, status) VALUES (gen_random_uuid(), $1::uuid, $2, $3, $4, now(), now(), 1, 'open') ON CONFLICT (project_id, fingerprint) DO UPDATE SET last_seen = now(), event_count = issues.event_count + 1, status = CASE WHEN issues.status IN ('resolved', 'ignored') THEN 'open' ELSE issues.status END RETURNING id::text, status", [project_id, fingerprint, title, level])?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("upsert_issue: no row returned")
  end
end

# Insert an event into the events hypertable.
# Uses Repo.query_raw due to the large number of columns (20+).
# Returns the generated event UUID.
pub fn insert_event(pool :: PoolHandle, project_id :: String, issue_id :: String, event_id :: String, timestamp :: String, platform :: String, level :: String, message :: String, exception_type :: String, exception_value :: String, stacktrace_json :: String, environment :: String, release_tag :: String, server_name :: String, tags_json :: String, extra_json :: String, contexts_json :: String, sdk_name :: String, sdk_version :: String, fingerprint :: String) -> String!String do
  let rows = Repo.query_raw(pool, "INSERT INTO events (project_id, issue_id, event_id, timestamp, platform, level, message, exception_type, exception_value, stacktrace_json, environment, release_tag, server_name, tags_json, extra_json, contexts_json, sdk_name, sdk_version, fingerprint) VALUES ($1::uuid, $2::uuid, $3, $4::timestamptz, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19) RETURNING id::text", [project_id, issue_id, event_id, timestamp, platform, level, message, exception_type, exception_value, stacktrace_json, environment, release_tag, server_name, tags_json, extra_json, contexts_json, sdk_name, sdk_version, fingerprint])?
  if List.length(rows) > 0 do
    Ok(Map.get(List.head(rows), "id"))
  else
    Err("insert_event: no row returned")
  end
end

# Get rate limit configuration for an organization.
# Returns the config row with events_per_minute and burst_limit, or Err("not found").
pub fn get_rate_limit_config(pool :: PoolHandle, org_id :: String) -> Map<String, String>!String do
  let q = Query.from(RateLimitConfig.__table__())
    |> Query.where_raw("org_id = ?::uuid", [org_id])
    |> Query.select_raw(["id::text", "org_id::text", "events_per_minute::text", "burst_limit::text", "created_at::text", "updated_at::text"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("not found")
  end
end

# Get all active scrub rules for an organization.
# Returns a list of rule rows with pattern, replacement, and description.
pub fn get_active_scrub_rules(pool :: PoolHandle, org_id :: String) -> List<Map<String, String>>!String do
  let q = Query.from(ScrubRule.__table__())
    |> Query.where_raw("org_id = ?::uuid AND is_active = true", [org_id])
    |> Query.select_raw(["id::text", "org_id::text", "pattern", "replacement", "COALESCE(description, '') AS description", "created_at::text"])
    |> Query.order_by_raw("created_at")
  Repo.all(pool, q)
end

# Validate an API key for ingestion and resolve project + org context.
# JOINs api_keys with projects to get project_id, org_id, and project name in one query.
# Filters WHERE key_hash matches AND key is not revoked.
# This is the core authentication query for all ingestion endpoints.
pub fn validate_api_key_for_ingest(pool :: PoolHandle, key_hash :: String) -> Map<String, String>!String do
  let q = Query.from(ApiKey.__table__())
    |> Query.join_as(:inner, Project.__table__(), "p", "p.id = api_keys.project_id")
    |> Query.where(:key_hash, key_hash)
    |> Query.where_raw("api_keys.revoked_at IS NULL", [])
    |> Query.select_raw(["api_keys.project_id::text", "p.org_id::text", "p.name AS project_name"])
  let rows = Repo.all(pool, q)?
  if List.length(rows) > 0 do
    Ok(List.head(rows))
  else
    Err("invalid API key")
  end
end

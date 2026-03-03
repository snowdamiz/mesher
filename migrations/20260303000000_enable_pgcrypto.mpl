# Migration: Enable pgcrypto extension
# Required for crypt() function used in password verification.
# gen_random_uuid() also requires this extension for session ID generation.
# This migration runs BEFORE create_public_tables (alphabetical ordering).

fn up(pool) -> Int!String do
  let _ = Pool.execute(pool, "CREATE EXTENSION IF NOT EXISTS pgcrypto", [])?
  Ok(0)
end

fn down(pool) -> Int!String do
  let _ = Pool.execute(pool, "DROP EXTENSION IF EXISTS pgcrypto", [])?
  Ok(0)
end

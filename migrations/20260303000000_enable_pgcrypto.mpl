# Migration: Enable pgcrypto extension
# Required for bcrypt password hashing via crypt()/gen_salt('bf').
# Mesh Crypto stdlib has sha256/sha512/uuid4 but no bcrypt -- bcrypt is
# delegated to pgcrypto. UUID and SHA-256 operations use native Mesh Crypto.
# This migration runs BEFORE create_public_tables (alphabetical ordering).

fn up(pool) -> Int!String do
  let _ = Pool.execute(pool, "CREATE EXTENSION IF NOT EXISTS pgcrypto", [])?
  Ok(0)
end

fn down(pool) -> Int!String do
  let _ = Pool.execute(pool, "DROP EXTENSION IF EXISTS pgcrypto", [])?
  Ok(0)
end

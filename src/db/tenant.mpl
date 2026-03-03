# Tenant isolation via schema-per-org has been removed in Phase 01.1.
# Projects and api_keys now use org_id FK in the public schema.
# All tenant-scoped queries filter by org_id WHERE clause.
# This file is kept as a historical note and will be removed in Phase 01.2 (repo reorganization).

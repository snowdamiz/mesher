# Organization and project model structs for the Mesher data layer.
# All structs use deriving(Schema, Json, Row) for ORM integration.
# Projects and ApiKeys are in the public schema with org_id FK (no schema-per-org).

pub struct Organization do
  table "organizations"
  id :: String
  name :: String
  slug :: String
  created_at :: String
  has_many :projects, Project
  has_many :org_memberships, OrgMembership
end deriving(Schema, Json, Row)

pub struct Project do
  table "projects"
  id :: String
  org_id :: String
  name :: String
  created_at :: String
  belongs_to :org, Organization
  has_many :api_keys, ApiKey
end deriving(Schema, Json, Row)

pub struct ApiKey do
  table "api_keys"
  id :: String
  project_id :: String
  key_hash :: String
  key_prefix :: String
  label :: String
  created_at :: String
  revoked_at :: Option<String>
  belongs_to :project, Project
end deriving(Schema, Json, Row)

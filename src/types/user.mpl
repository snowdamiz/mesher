# User-related model structs for the Mesher data layer.
# All structs use deriving(Schema, Json, Row) for ORM integration.
# password_hash is intentionally excluded from User struct (never expose to app code).

pub struct User do
  table "users"
  id :: String
  email :: String
  created_at :: String
  has_many :org_memberships, OrgMembership
  has_many :sessions, Session
end deriving(Schema, Json, Row)

pub struct OrgMembership do
  table "org_memberships"
  id :: String
  org_id :: String
  user_id :: String
  role :: String
  created_at :: String
  belongs_to :user, User
  belongs_to :org, Organization
end deriving(Schema, Json, Row)

pub struct Session do
  table "sessions"
  primary_key :token
  token :: String
  user_id :: String
  created_at :: String
  expires_at :: String
  belongs_to :user, User
end deriving(Schema, Json, Row)

pub struct Invite do
  table "invites"
  id :: String
  org_id :: String
  email :: String
  token :: String
  invited_by :: String
  expires_at :: String
  accepted_at :: Option<String>
  revoked_at :: Option<String>
  created_at :: String
  belongs_to :org, Organization
end deriving(Schema, Json, Row)

pub struct PasswordResetToken do
  table "password_reset_tokens"
  id :: String
  user_id :: String
  token_hash :: String
  expires_at :: String
  used_at :: Option<String>
  created_at :: String
  belongs_to :user, User
end deriving(Schema, Json, Row)

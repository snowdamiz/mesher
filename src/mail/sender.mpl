# Email sending module
#
# Provides a mock email sender for Phase 1.
# In production, this should be replaced with an HTTP-based transactional
# email API (SendGrid, Postmark, Mailgun) since Mesh has no SMTP client.
#
# The function signature is the contract -- real email delivery can be
# wired later by replacing the implementation.
#
# NOTE: To use actual email delivery, configure one of:
#   1. An SMTP-to-HTTP bridge service (e.g., mailhog for dev)
#   2. A transactional email service with HTTP API
#   3. Set SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS env vars
#      and implement Http.build POST to the service's HTTP API

# Send an email (mock implementation: logs to stdout).
# Returns Ok(0) on success.
pub fn send_email(to :: String, subject :: String, body :: String) -> Int!String do
  let _ = println("[EMAIL] To: #{to} | Subject: #{subject} | Body: #{body}")
  Ok(0)
end

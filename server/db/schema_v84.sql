-- Evidence of privacy notice acceptance for public contact submissions.
ALTER TABLE guest_support_requests
  ADD COLUMN IF NOT EXISTS privacy_notice_version VARCHAR(40),
  ADD COLUMN IF NOT EXISTS privacy_consent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS intake_source VARCHAR(40) NOT NULL DEFAULT 'website_contact';

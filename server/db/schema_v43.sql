CREATE TABLE IF NOT EXISTS user_legal_consents (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_type VARCHAR(50) NOT NULL,
  document_version VARCHAR(30) NOT NULL,
  accepted BOOLEAN NOT NULL,
  ip_address VARCHAR(100),
  user_agent VARCHAR(500),
  accepted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, consent_type, document_version)
);

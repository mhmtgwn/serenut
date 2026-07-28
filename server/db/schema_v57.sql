-- Support intake model: authenticated tickets and unverified guest requests

ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS requester_user_id VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS category VARCHAR(30) NOT NULL DEFAULT 'technical'
    CHECK (category IN ('technical', 'license', 'billing', 'account', 'usage', 'other')),
  ADD COLUMN IF NOT EXISTS intake_channel VARCHAR(30) NOT NULL DEFAULT 'customer_portal'
    CHECK (intake_channel IN ('customer_portal', 'admin', 'api'));

CREATE INDEX IF NOT EXISTS idx_support_tickets_requester
  ON support_tickets(requester_user_id);

CREATE TABLE IF NOT EXISTS guest_support_requests (
  id VARCHAR(100) PRIMARY KEY,
  reference_code VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(200) NOT NULL,
  email VARCHAR(320) NOT NULL,
  phone VARCHAR(50),
  company_name VARCHAR(250),
  customer_claim VARCHAR(30) NOT NULL DEFAULT 'not_registered'
    CHECK (customer_claim IN ('not_registered', 'cannot_login', 'unsure')),
  category VARCHAR(30) NOT NULL DEFAULT 'other'
    CHECK (category IN ('technical', 'license', 'billing', 'account', 'usage', 'sales', 'other')),
  subject VARCHAR(500) NOT NULL,
  message TEXT NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'unverified'
    CHECK (status IN ('unverified', 'under_review', 'converted', 'routed_to_sales', 'closed')),
  matched_company_id VARCHAR(100) REFERENCES companies(id) ON DELETE SET NULL,
  converted_ticket_id VARCHAR(100) REFERENCES support_tickets(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_guest_support_status_created
  ON guest_support_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_guest_support_email
  ON guest_support_requests(LOWER(email));

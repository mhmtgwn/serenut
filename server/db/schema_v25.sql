-- server/db/schema_v25.sql
-- Serenut OS -- Commercial Lifecycle V2 -- Phase 3 (Payment Bank Accounts & Bank Transfer Notifications)

-- ── 1. PAYMENT BANK ACCOUNTS ─────────────────────────────────────────────────
-- Platform-level bank accounts managed exclusively by sysadmin.
-- Replaces hardcoded IBAN env vars and system_settings keys.

CREATE TABLE IF NOT EXISTS payment_bank_accounts (
    id VARCHAR(100) PRIMARY KEY,
    bank_name VARCHAR(150) NOT NULL,
    account_holder VARCHAR(200) NOT NULL,
    iban VARCHAR(34) NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'TRY',
    branch_name VARCHAR(150),
    instructions TEXT,
    -- e.g. "Acıklama alanına referans kodunuzu yazın"
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Seed from existing system_settings if present (best-effort; idempotent)
INSERT INTO payment_bank_accounts (
    id, bank_name, account_holder, iban, currency, branch_name, instructions, is_active, display_order
)
SELECT
    'pba-default',
    COALESCE((SELECT value FROM system_settings WHERE key = 'iban_bank' LIMIT 1),   'Yapı Kredi Bankası A.Ş.'),
    COALESCE((SELECT value FROM system_settings WHERE key = 'iban_owner' LIMIT 1),  'Serenut Yazılım Teknolojileri Ltd. Şti.'),
    COALESCE((SELECT value FROM system_settings WHERE key = 'iban_number' LIMIT 1), 'TR00 0000 0000 0000 0000 0000 00'),
    'TRY',
    COALESCE((SELECT value FROM system_settings WHERE key = 'iban_branch' LIMIT 1), NULL),
    'Havale açıklama alanına referans kodunuzu yazınız.',
    TRUE,
    0
WHERE NOT EXISTS (SELECT 1 FROM payment_bank_accounts WHERE id = 'pba-default');

-- ── 2. BANK TRANSFER NOTIFICATIONS ───────────────────────────────────────────
-- Stores each customer's bank transfer claim with receipt and admin review fields.

CREATE TABLE IF NOT EXISTS bank_transfer_notifications (
    id VARCHAR(100) PRIMARY KEY,
    invoice_id VARCHAR(100) REFERENCES invoices(id) ON DELETE SET NULL,
    company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    bank_account_id VARCHAR(100) REFERENCES payment_bank_accounts(id) ON DELETE SET NULL,
    reference_code VARCHAR(50) NOT NULL UNIQUE,
    -- auto-generated: SRNTT-YYYYMMDD-XXXX
    sender_name VARCHAR(200),
    sender_bank VARCHAR(150),
    transfer_date DATE,
    transfer_description TEXT,
    receipt_file_path VARCHAR(500),
    -- uploaded dekont file path
    status VARCHAR(50) NOT NULL DEFAULT 'pending_review',
    -- pending_review | approved | rejected
    admin_note TEXT,
    reviewed_by VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bank_transfer_status
  ON bank_transfer_notifications(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_bank_transfer_company
  ON bank_transfer_notifications(company_id);

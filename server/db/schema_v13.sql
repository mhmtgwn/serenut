-- Migration v13: Support Tickets + Trial/Subscription FSM Columns
-- Serenut OS V1 — State Machine Implementation
-- Blueprint: state_machine_specification.md

-- Drop old tables to ensure clean V1 support schema
DROP TABLE IF EXISTS ticket_internal_notes CASCADE;
DROP TABLE IF EXISTS support_ticket_messages CASCADE;
DROP TABLE IF EXISTS support_tickets CASCADE;

-- ── SUPPORT TICKETS ──────────────────────────────────────────────────────────
-- Support Ticket FSM: open → in_progress → pending_customer → resolved → closed
CREATE TABLE support_tickets (
    id              VARCHAR(100)  PRIMARY KEY,
    company_id      VARCHAR(100)  REFERENCES companies(id) ON DELETE SET NULL,
    subject         VARCHAR(500)  NOT NULL,
    body            TEXT,
    priority        VARCHAR(10)   NOT NULL DEFAULT 'P3'
                                  CHECK (priority IN ('P1', 'P2', 'P3', 'P4')),
    status          VARCHAR(30)   NOT NULL DEFAULT 'open'
                                  CHECK (status IN ('open', 'in_progress', 'pending_customer', 'resolved', 'closed')),
    assigned_to     VARCHAR(100), -- sysadmin user reference (free text for now)
    logs_snapshot   TEXT,         -- telemetry log attachment
    support_pin     VARCHAR(10),  -- one-time 8-digit remote support PIN
    sla_deadline_at TIMESTAMP WITH TIME ZONE,
    resolved_at     TIMESTAMP WITH TIME ZONE,
    closed_at       TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_company    ON support_tickets(company_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status     ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_priority   ON support_tickets(priority);

-- Recreate dependent table support_ticket_messages
CREATE TABLE support_ticket_messages (
    id VARCHAR(100) PRIMARY KEY,
    ticket_id VARCHAR(100) REFERENCES support_tickets(id) ON DELETE CASCADE,
    sender_id VARCHAR(100) NOT NULL,
    sender_name VARCHAR(150) NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Recreate dependent table ticket_internal_notes
CREATE TABLE ticket_internal_notes (
    id VARCHAR(100) PRIMARY KEY,
    ticket_id VARCHAR(100) REFERENCES support_tickets(id) ON DELETE CASCADE,
    author_id VARCHAR(100) NOT NULL,
    author_name VARCHAR(150) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets FORCE ROW LEVEL SECURITY;

ALTER TABLE support_ticket_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_ticket_messages FORCE ROW LEVEL SECURITY;

ALTER TABLE ticket_internal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_internal_notes FORCE ROW LEVEL SECURITY;

-- Tenant isolation policies with admin bypass
CREATE POLICY tenant_isolation ON support_tickets FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

CREATE POLICY tenant_isolation ON support_ticket_messages FOR ALL USING (
    ticket_id IN (SELECT id FROM support_tickets WHERE company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
);

CREATE POLICY tenant_isolation ON ticket_internal_notes FOR ALL USING (
    current_setting('app.bypass_rls', true) = 'true'
);

-- ── SUBSCRIPTION FSM COLUMNS ─────────────────────────────────────────────────
-- Add trial tracking and FSM state to subscriptions (or companies if no subscriptions table)
-- First ensure subscriptions table has required columns

DO $$
BEGIN
  -- trial_started_at: NULL until first login (FSM rule)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'trial_started_at'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN trial_started_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- trial_ends_at: trial_started_at + 30 days, set by server on first login
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'trial_ends_at'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN trial_ends_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- suspended_at: timestamp when subscription was suspended
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'suspended_at'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN suspended_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- cancelled_at: timestamp when user requested cancellation
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'cancelled_at'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN cancelled_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- deletion_scheduled_at: 6 months after cancellation (data retention)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'deletion_scheduled_at'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN deletion_scheduled_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- payment_retry_count: tracks number of failed payment retries (max 4)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'payment_retry_count'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN payment_retry_count INTEGER DEFAULT 0;
  END IF;

  -- next_retry_at: next scheduled payment retry timestamp
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'subscriptions' AND column_name = 'next_retry_at'
  ) THEN
    ALTER TABLE subscriptions ADD COLUMN next_retry_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- ── LICENSE FSM COLUMN ────────────────────────────────────────────────────────
DO $$
BEGIN
  -- fsm_state: tracks license FSM (unassigned | active | expired | suspended)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'fsm_state'
  ) THEN
    ALTER TABLE licenses ADD COLUMN fsm_state VARCHAR(20) DEFAULT 'unassigned'
      CHECK (fsm_state IN ('unassigned', 'active', 'expired', 'suspended'));
  END IF;

  -- suspended_at: when sysadmin blocked this license
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'suspended_at'
  ) THEN
    ALTER TABLE licenses ADD COLUMN suspended_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- suspended_reason: reason for suspension (abuse | chargeback | manual)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'licenses' AND column_name = 'suspended_reason'
  ) THEN
    ALTER TABLE licenses ADD COLUMN suspended_reason VARCHAR(50);
  END IF;
END $$;

-- ── DEVICE SWAP TRACKING ─────────────────────────────────────────────────────
-- Monthly swap limit enforcement (max 2 per month per license)
CREATE TABLE IF NOT EXISTS device_swap_log (
    id          VARCHAR(100) PRIMARY KEY,
    license_id  VARCHAR(100) REFERENCES licenses(id) ON DELETE CASCADE,
    device_id   VARCHAR(100),
    action      VARCHAR(20)  NOT NULL CHECK (action IN ('activate', 'deactivate')),
    performed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_device_swap_log_license ON device_swap_log(license_id);
CREATE INDEX IF NOT EXISTS idx_device_swap_log_month   ON device_swap_log(license_id, performed_at);

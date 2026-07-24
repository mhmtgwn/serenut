-- Rollback v13: Remove support_tickets, FSM columns, swap log
-- Run this to revert migration v13

-- Drop new tables
DROP TABLE IF EXISTS device_swap_log;
DROP TABLE IF EXISTS support_tickets;

-- Remove subscription FSM columns
ALTER TABLE subscriptions DROP COLUMN IF EXISTS trial_started_at;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS trial_ends_at;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS suspended_at;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS cancelled_at;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS deletion_scheduled_at;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS payment_retry_count;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS next_retry_at;

-- Remove license FSM columns
ALTER TABLE licenses DROP COLUMN IF EXISTS fsm_state;
ALTER TABLE licenses DROP COLUMN IF EXISTS suspended_at;
ALTER TABLE licenses DROP COLUMN IF EXISTS suspended_reason;

-- Remove from schema_migrations
DELETE FROM schema_migrations WHERE version = 13;

-- Remove the retired remote-support PIN mechanism.
-- Authorization is enforced by authenticated roles and tenant isolation.
ALTER TABLE support_tickets
  DROP COLUMN IF EXISTS support_pin;

-- Only advertise methods that have a complete API, UI and acceptance suite.
ALTER TABLE password_recovery_requests
  DROP CONSTRAINT IF EXISTS password_recovery_requests_method_check;
ALTER TABLE password_recovery_requests
  ADD CONSTRAINT password_recovery_requests_method_check
  CHECK (method IN ('recovery_code','admin_assisted'));

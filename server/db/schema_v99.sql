-- schema_v99.sql
-- Financial ledger integrity trigger update:
-- Aligns PostgreSQL customer balance calculation with client SQLite ledger logic.
-- Incorporates 'manual_debt', 'cancellation', and 'refund' transactions cleanly.

CREATE OR REPLACE FUNCTION update_customer_balance_from_transaction()
RETURNS TRIGGER AS $$
DECLARE affected_customer VARCHAR(100);
BEGIN
  IF TG_OP = 'DELETE' THEN
    affected_customer := OLD.customer_id;
  ELSE
    affected_customer := NEW.customer_id;
  END IF;
  IF affected_customer IS NOT NULL THEN
    UPDATE customers SET balance=COALESCE((
      SELECT SUM(CASE
        WHEN type IN ('sale', 'manual_debt') THEN (CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
        WHEN type IN ('payment', 'collection') THEN -paid_amount
        WHEN type = 'cancellation' THEN -(CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
        WHEN type = 'refund' AND paid_amount = 0 THEN -amount
        ELSE 0 END)
      FROM financial_transactions
      WHERE customer_id=affected_customer AND is_deleted=FALSE
    ),0),updated_at=NOW() WHERE id=affected_customer;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

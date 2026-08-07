CREATE UNIQUE INDEX IF NOT EXISTS uq_refunds_external_reference
  ON refunds(company_id,refund_method,external_reference)
  WHERE external_reference IS NOT NULL;

CREATE OR REPLACE FUNCTION prevent_refund_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'refund_records_are_immutable' USING ERRCODE='55000';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_refunds_immutable ON refunds;
CREATE TRIGGER trg_refunds_immutable
BEFORE UPDATE OR DELETE ON refunds
FOR EACH ROW EXECUTE FUNCTION prevent_refund_mutation();

DROP TRIGGER IF EXISTS trg_refund_items_immutable ON refund_items;
CREATE TRIGGER trg_refund_items_immutable
BEFORE UPDATE OR DELETE ON refund_items
FOR EACH ROW EXECUTE FUNCTION prevent_refund_mutation();

ALTER TABLE inventory_movements
  ADD CONSTRAINT chk_inventory_movement_type
  CHECK(movement_type IN ('sale','refund','adjustment','transfer')) NOT VALID;
ALTER TABLE inventory_movements VALIDATE CONSTRAINT chk_inventory_movement_type;

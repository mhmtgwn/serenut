-- Complete tenant isolation for tables that gained company_id after the base schema.
DO $$
DECLARE table_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'branches','client_health_reports','company_sms_gateways','device_app_versions',
    'password_recovery_requests','password_security_events','roles','sessions',
    'update_download_logs'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', table_name);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I FOR ALL USING '
      '(company_id = current_tenant_id() OR current_setting(''app.bypass_rls'', true) = ''true'') '
      'WITH CHECK (company_id = current_tenant_id() OR current_setting(''app.bypass_rls'', true) = ''true'')',
      table_name
    );
  END LOOP;
END $$;

-- Existing rows were audited before validation; make the protections authoritative.
ALTER TABLE sales VALIDATE CONSTRAINT chk_sales_amounts_valid;
ALTER TABLE sale_items VALIDATE CONSTRAINT chk_sale_items_amounts;
ALTER TABLE financial_transactions VALIDATE CONSTRAINT chk_financial_amounts_non_negative;
ALTER TABLE subscriptions VALIDATE CONSTRAINT chk_subscription_period;
ALTER TABLE invoices VALIDATE CONSTRAINT chk_invoice_amount_non_negative;
ALTER TABLE license_entitlements VALIDATE CONSTRAINT chk_entitlement_period;

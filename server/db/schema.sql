-- PostgreSQL schema v1.0 for Serenut POS SaaS backend

-- 1. SaaS & Tenants
CREATE TABLE IF NOT EXISTS companies (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    tax_number VARCHAR(50) NOT NULL UNIQUE,
    tax_office VARCHAR(150),
    phone VARCHAR(50),
    email VARCHAR(150),
    address TEXT,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Identity & Access Management (RBAC)
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    username VARCHAR(100),
    token_version INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    last_login_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_email_per_company UNIQUE (email, company_id)
);

CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(100) PRIMARY KEY,
    user_id VARCHAR(100) REFERENCES users(id) ON DELETE CASCADE,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    refresh_token VARCHAR(255) UNIQUE NOT NULL,
    ip_address VARCHAR(50),
    user_agent VARCHAR(255),
    is_revoked BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE IF NOT EXISTS roles (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE IF NOT EXISTS permissions (
    id VARCHAR(100) PRIMARY KEY,
    code VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id VARCHAR(100) REFERENCES roles(id) ON DELETE CASCADE,
    permission_id VARCHAR(100) REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_roles (
    user_id VARCHAR(100) REFERENCES users(id) ON DELETE CASCADE,
    role_id VARCHAR(100) REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- 3. POS Business Entities
CREATE TABLE IF NOT EXISTS products (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    quantity INTEGER NOT NULL DEFAULT 0,
    category VARCHAR(100),
    vat INTEGER DEFAULT 0,
    image_path VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active',
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customers (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    credit_limit DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    status VARCHAR(50) DEFAULT 'active',
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stores (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Sales & Invoicing
CREATE TABLE IF NOT EXISTS sales (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    customer_id VARCHAR(100) REFERENCES customers(id) ON DELETE SET NULL,
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    paid_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    payment_method VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'completed',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    idempotency_key VARCHAR(255) UNIQUE,
    is_synced INTEGER DEFAULT 0,
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(100),
    created_by VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS sale_items (
    id VARCHAR(100) PRIMARY KEY,
    sale_id VARCHAR(100) REFERENCES sales(id) ON DELETE CASCADE,
    product_id VARCHAR(100) REFERENCES products(id) ON DELETE SET NULL,
    quantity DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    unit_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    subtotal DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS financial_transactions (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL, -- 'sale', 'payment', 'refund', 'collection'
    customer_id VARCHAR(100) REFERENCES customers(id) ON DELETE SET NULL,
    amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    paid_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    debt_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    date TIMESTAMP WITH TIME ZONE NOT NULL,
    reference_id VARCHAR(100),
    logical_clock INTEGER DEFAULT 0,
    device_id VARCHAR(100),
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(100),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Devices & Licensing
CREATE TABLE IF NOT EXISTS devices (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    store_id VARCHAR(100) REFERENCES stores(id) ON DELETE SET NULL,
    device_hash VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    status VARCHAR(50) DEFAULT 'active',
    last_active_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS licenses (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    license_key VARCHAR(100) UNIQUE NOT NULL,
    tier VARCHAR(50) NOT NULL DEFAULT 'pro',
    allowed_devices_count INTEGER DEFAULT 1,
    status VARCHAR(50) DEFAULT 'active',
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS device_licenses (
    device_id VARCHAR(100) REFERENCES devices(id) ON DELETE CASCADE,
    license_id VARCHAR(100) REFERENCES licenses(id) ON DELETE CASCADE,
    PRIMARY KEY (device_id, license_id)
);

-- 6. Subscription & Billing (SaaS)
CREATE TABLE IF NOT EXISTS plans (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(10) DEFAULT 'TRY',
    billing_interval VARCHAR(50) DEFAULT 'monthly',
    features JSONB
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    plan_id VARCHAR(100) REFERENCES plans(id) ON DELETE RESTRICT,
    status VARCHAR(50) DEFAULT 'active',
    current_period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    current_period_end TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE IF NOT EXISTS invoices (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    subscription_id VARCHAR(100) REFERENCES subscriptions(id) ON DELETE SET NULL,
    amount DECIMAL(12, 2) NOT NULL,
    status VARCHAR(50) DEFAULT 'paid',
    due_at TIMESTAMP WITH TIME ZONE,
    paid_at TIMESTAMP WITH TIME ZONE
);

-- 7. OTA App Versions
CREATE TABLE IF NOT EXISTS app_versions (
    id VARCHAR(100) PRIMARY KEY,
    version_code VARCHAR(50) NOT NULL UNIQUE,
    platform VARCHAR(50) NOT NULL,
    download_url VARCHAR(500) NOT NULL,
    sha256_hash VARCHAR(64) NOT NULL,
    is_mandatory BOOLEAN DEFAULT FALSE,
    release_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. Senkronizasyon (Sync)
CREATE TABLE IF NOT EXISTS sync_queue (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    device_id VARCHAR(100) REFERENCES devices(id) ON DELETE CASCADE,
    entity_type VARCHAR(100) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. Telemetry & Audit
CREATE TABLE IF NOT EXISTS crash_logs (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    device_id VARCHAR(100) REFERENCES devices(id) ON DELETE SET NULL,
    error_message TEXT NOT NULL,
    stack_trace TEXT,
    app_version VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    user_id VARCHAR(100) NOT NULL,
    user_name VARCHAR(150) NOT NULL DEFAULT 'System',
    action VARCHAR(100) NOT NULL,
    entity VARCHAR(100),
    entity_type VARCHAR(100) NOT NULL DEFAULT 'Unknown',
    entity_id VARCHAR(100),
    old_value JSONB,
    new_value JSONB,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(50),
    user_agent VARCHAR(255) NOT NULL DEFAULT 'Unknown',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ── CUSTOMER BALANCE EVENT SOURCING TRIGGER ──
CREATE OR REPLACE FUNCTION update_customer_balance_from_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        IF NEW.customer_id IS NOT NULL THEN
            UPDATE customers 
            SET balance = COALESCE((
                SELECT SUM(debt_amount) - SUM(paid_amount) 
                FROM financial_transactions 
                WHERE customer_id = NEW.customer_id AND is_deleted = FALSE
            ), 0.00),
            updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.customer_id;
        END IF;
    END IF;
    
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        IF OLD.customer_id IS NOT NULL THEN
            UPDATE customers 
            SET balance = COALESCE((
                SELECT SUM(debt_amount) - SUM(paid_amount) 
                FROM financial_transactions 
                WHERE customer_id = OLD.customer_id AND is_deleted = FALSE
            ), 0.00),
            updated_at = CURRENT_TIMESTAMP
            WHERE id = OLD.customer_id;
        END IF;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_recalculate_customer_balance
AFTER INSERT OR UPDATE OR DELETE ON financial_transactions
FOR EACH ROW
EXECUTE FUNCTION update_customer_balance_from_transaction();

-- ── ROW LEVEL SECURITY (RLS) & TENANT ISOLATION ──

-- Function to safely fetch the current tenant context from session variables
CREATE OR REPLACE FUNCTION current_tenant_id() RETURNS VARCHAR AS $$
BEGIN
    RETURN NULLIF(current_setting('app.current_company_id', true), '');
END;
$$ LANGUAGE plpgsql;

-- 1. Enable & Force RLS on Multi-Tenant Tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE stores FORCE ROW LEVEL SECURITY;

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers FORCE ROW LEVEL SECURITY;

ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales FORCE ROW LEVEL SECURITY;

ALTER TABLE financial_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_transactions FORCE ROW LEVEL SECURITY;

ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE ROW LEVEL SECURITY;

ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE licenses FORCE ROW LEVEL SECURITY;

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions FORCE ROW LEVEL SECURITY;

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;

ALTER TABLE sync_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_queue FORCE ROW LEVEL SECURITY;

ALTER TABLE crash_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE crash_logs FORCE ROW LEVEL SECURITY;

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

-- 2. Create Isolation Policies (Enforces company_id matching current_tenant_id)
CREATE POLICY tenant_isolation ON users FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON stores FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON products FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON customers FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON sales FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON financial_transactions FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON devices FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON licenses FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON subscriptions FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON invoices FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON sync_queue FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON crash_logs FOR ALL USING (company_id = current_tenant_id());
CREATE POLICY tenant_isolation ON audit_logs FOR ALL USING (company_id = current_tenant_id());


-- schema_v103.sql
-- Fındık ve Emanet Depo Modülü (Warehouses, Escrow, Movements, Price Cuts)

-- 1. Depolar Tablosu
CREATE TABLE IF NOT EXISTS warehouses (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  location TEXT,
  capacity_kg NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  current_stock_kg NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  average_rendiment NUMERIC(5, 2) NOT NULL DEFAULT 50.00,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_warehouses_company ON warehouses(company_id);
ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON warehouses FOR ALL USING (company_id = NULLIF(current_setting('app.current_company_id', true), ''));

-- 2. Müşteri Emanet Fındık Defteri (Her üreticinin emanete bıraktığı fındık partileri)
CREATE TABLE IF NOT EXISTS customer_hazelnut_escrow (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  customer_id VARCHAR(100) NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  warehouse_id VARCHAR(100) NOT NULL REFERENCES warehouses(id) ON DELETE RESTRICT,
  receipt_no VARCHAR(100),
  gross_kg NUMERIC(14, 2) NOT NULL,
  sack_count INTEGER NOT NULL DEFAULT 0,
  tare_kg NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  net_kg NUMERIC(14, 2) NOT NULL,
  rendiment NUMERIC(5, 2) NOT NULL DEFAULT 50.00,
  remaining_kg NUMERIC(14, 2) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'active', -- 'active', 'partially_cut', 'closed'
  notes TEXT,
  created_by VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_hazelnut_escrow_company ON customer_hazelnut_escrow(company_id);
CREATE INDEX IF NOT EXISTS idx_hazelnut_escrow_customer ON customer_hazelnut_escrow(customer_id);
CREATE INDEX IF NOT EXISTS idx_hazelnut_escrow_warehouse ON customer_hazelnut_escrow(warehouse_id);
ALTER TABLE customer_hazelnut_escrow ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON customer_hazelnut_escrow FOR ALL USING (company_id = NULLIF(current_setting('app.current_company_id', true), ''));

-- 3. Depo Fındık Hareketleri (Fiziksel giren/çıkan ekstre)
CREATE TABLE IF NOT EXISTS warehouse_hazelnut_movements (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  warehouse_id VARCHAR(100) NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  movement_type VARCHAR(50) NOT NULL, -- 'ESCROW_IN', 'PURCHASE_IN', 'SALE_OUT', 'TRANSFER_IN', 'TRANSFER_OUT', 'RETURN_OUT'
  quantity_kg NUMERIC(14, 2) NOT NULL,
  rendiment NUMERIC(5, 2) NOT NULL DEFAULT 50.00,
  balance_kg_after NUMERIC(14, 2) NOT NULL,
  average_rendiment_after NUMERIC(5, 2) NOT NULL,
  reference_id VARCHAR(100),
  description TEXT,
  created_by VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_hazelnut_movements_warehouse ON warehouse_hazelnut_movements(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_hazelnut_movements_company ON warehouse_hazelnut_movements(company_id);
ALTER TABLE warehouse_hazelnut_movements ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON warehouse_hazelnut_movements FOR ALL USING (company_id = NULLIF(current_setting('app.current_company_id', true), ''));

-- 4. Fındık Fiyat Kesim Bordrosu (Emanetin TL'ye / Satışa dönüşüm kayıtları)
CREATE TABLE IF NOT EXISTS hazelnut_price_cuts (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  escrow_id VARCHAR(100) NOT NULL REFERENCES customer_hazelnut_escrow(id) ON DELETE RESTRICT,
  customer_id VARCHAR(100) NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  cut_kg NUMERIC(14, 2) NOT NULL,
  rendiment NUMERIC(5, 2) NOT NULL,
  base_price_50 NUMERIC(12, 2) NOT NULL,
  effective_price NUMERIC(12, 2) NOT NULL,
  total_amount NUMERIC(14, 2) NOT NULL,
  settlement_type VARCHAR(50) NOT NULL DEFAULT 'ACCOUNT_CREDIT', -- 'CASH_PAID', 'OFFSET_DEBT', 'ACCOUNT_CREDIT'
  financial_transaction_id VARCHAR(100),
  notes TEXT,
  created_by VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_hazelnut_price_cuts_escrow ON hazelnut_price_cuts(escrow_id);
CREATE INDEX IF NOT EXISTS idx_hazelnut_price_cuts_customer ON hazelnut_price_cuts(customer_id);
CREATE INDEX IF NOT EXISTS idx_hazelnut_price_cuts_company ON hazelnut_price_cuts(company_id);
ALTER TABLE hazelnut_price_cuts ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON hazelnut_price_cuts FOR ALL USING (company_id = NULLIF(current_setting('app.current_company_id', true), ''));


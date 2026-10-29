-- schema_v108.sql
-- Canonical web traffic analytics, dwell time and funnel events schema

CREATE TABLE IF NOT EXISTS web_page_visits (
  id BIGSERIAL PRIMARY KEY,
  page_path VARCHAR(120) NOT NULL,
  visitor_hash VARCHAR(64) NOT NULL,
  traffic_source VARCHAR(60) NOT NULL DEFAULT 'Direkt Giriş',
  device_type VARCHAR(20) NOT NULL DEFAULT 'Masaüstü',
  session_id VARCHAR(64),
  utm_source VARCHAR(80),
  utm_medium VARCHAR(80),
  utm_campaign VARCHAR(100),
  duration_seconds INT NOT NULL DEFAULT 0,
  max_scroll_pct INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_web_page_visits_created_at ON web_page_visits(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_web_page_visits_session ON web_page_visits(session_id);
CREATE INDEX IF NOT EXISTS idx_web_page_visits_visitor ON web_page_visits(visitor_hash);

CREATE TABLE IF NOT EXISTS web_analytics_events (
  id BIGSERIAL PRIMARY KEY,
  session_id VARCHAR(64) NOT NULL,
  visitor_hash VARCHAR(64) NOT NULL,
  event_name VARCHAR(60) NOT NULL,
  event_category VARCHAR(40) NOT NULL DEFAULT 'interaction',
  event_label VARCHAR(150),
  page_path VARCHAR(120) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_web_analytics_events_created_at ON web_analytics_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_web_analytics_events_name ON web_analytics_events(event_name);

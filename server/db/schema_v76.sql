-- Legacy license projections are still read by installed clients. Keep their
-- mutation timestamp explicit so every canonical lifecycle transition can be
-- observed consistently by admin, API and synchronization consumers.
ALTER TABLE licenses
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

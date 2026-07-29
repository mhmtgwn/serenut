-- Company logos may be stored as compact data URLs so the same logo is
-- available to every POS device and the customer web panel.
ALTER TABLE companies
  ALTER COLUMN logo_url TYPE TEXT;

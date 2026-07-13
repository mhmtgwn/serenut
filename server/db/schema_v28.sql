-- server/db/schema_v28.sql
-- Sprint 2: RTR Grace Period Security - Add replaced_by column to link rotated sessions

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS replaced_by VARCHAR(100) REFERENCES sessions(id) ON DELETE SET NULL;

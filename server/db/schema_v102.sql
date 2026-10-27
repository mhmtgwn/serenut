-- schema_v102.sql
-- Emergency sysadmin credential recovery and unlock (one-way bcrypt digest only)

DO $$
DECLARE
  v_role_id VARCHAR(100);
  v_updated_count INTEGER := 0;
  v_hash TEXT := '$2b$12$T5Z6ojD3BXR1L4hbwl.epesutHysluMpX5jF1DbBg2tMDiN.gvZPS';
BEGIN
  PERFORM set_config('app.bypass_rls', 'true', true);

  INSERT INTO companies (id, name, tax_number, tax_office, status)
  VALUES ('serenut_cloud', 'Serenut Platform', '0000000000', 'Platform', 'active')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO roles (id, name, description)
  VALUES ('sysadmin', 'sysadmin', 'Serenut platform system administrator')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_role_id FROM roles WHERE name = 'sysadmin' LIMIT 1;

  UPDATE users
  SET password_hash = v_hash,
      is_active = TRUE,
      deleted_at = NULL,
      failed_login_attempts = 0,
      locked_until = NULL,
      email_verified_at = COALESCE(email_verified_at, NOW()),
      token_version = COALESCE(token_version, 0) + 1,
      updated_at = NOW()
  WHERE id IN (
    SELECT ur.user_id
    FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name = 'sysadmin'
  );

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  IF v_updated_count = 0 AND v_role_id IS NOT NULL THEN
    INSERT INTO users (id, company_id, name, email, password_hash, is_active, email_verified_at)
    VALUES ('sysadmin-primary', 'serenut_cloud', 'Platform Yöneticisi', 'admin@serenut.com', v_hash, TRUE, NOW())
    ON CONFLICT (email) DO UPDATE
      SET password_hash = EXCLUDED.password_hash,
          is_active = TRUE,
          deleted_at = NULL,
          failed_login_attempts = 0,
          locked_until = NULL,
          email_verified_at = COALESCE(users.email_verified_at, NOW()),
          token_version = COALESCE(users.token_version, 0) + 1,
          updated_at = NOW();

    INSERT INTO user_roles (user_id, role_id)
    SELECT id, v_role_id FROM users WHERE LOWER(email) = 'admin@serenut.com'
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE sessions
  SET is_revoked = TRUE, updated_at = NOW()
  WHERE user_id IN (
    SELECT ur.user_id
    FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    WHERE r.name = 'sysadmin'
  );
END $$;

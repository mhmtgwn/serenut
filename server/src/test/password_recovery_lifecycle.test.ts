import assert from 'assert';
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { AuthService } from '../modules/auth/auth.service';
import { PasswordRecoveryService } from '../modules/auth/password-recovery.service';
import request from 'supertest';
import { app } from '../server';

async function setup(): Promise<void> {
  const client = await pgPool.connect();
  try { await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public;'); }
  finally { client.release(); }
  await runMigrations(pgPool);
}

async function seedUser(client: any, id: string, companyId: string, email: string, role: string, password = 'OldPassword!123') {
  await client.query(
    `INSERT INTO users(id,company_id,name,email,password_hash,is_active,email_verified_at)
     VALUES($1,$2,$3,$4,$5,TRUE,NOW())`,
    [id, companyId, id, email, await AuthService.hashPassword(password)],
  );
  await client.query(`INSERT INTO roles(id,name) VALUES($1,$1) ON CONFLICT DO NOTHING`, [role]);
  const roleRow = await client.query('SELECT id FROM roles WHERE name=$1', [role]);
  await client.query('INSERT INTO user_roles(user_id,role_id) VALUES($1,$2)', [id, roleRow.rows[0].id]);
}

async function run(): Promise<void> {
  await setup();
  const client = await pgPool.connect();
  let ownerCodes: string[] = [];
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    await client.query(`INSERT INTO companies(id,name,tax_number,status) VALUES
      ('recovery-company','Recovery Market','1234567890','active'),
      ('other-company','Other Market','9876543210','active'),
      ('serenut-admin','Serenut Admin','1111111111','active')`);
    await seedUser(client, 'owner-user', 'recovery-company', 'owner@recovery.test', 'owner');
    await seedUser(client, 'employee-user', 'recovery-company', 'employee@recovery.test', 'employee');
    await seedUser(client, 'blocked-employee', 'recovery-company', 'blocked@recovery.test', 'employee');
    await seedUser(client, 'other-owner', 'other-company', 'owner@other.test', 'owner');
    await seedUser(client, 'sysadmin-a', 'serenut-admin', 'a@admin.test', 'sysadmin');
    await seedUser(client, 'sysadmin-b', 'serenut-admin', 'b@admin.test', 'sysadmin');
    await seedUser(client, 'sysadmin-target', 'serenut-admin', 'target@admin.test', 'sysadmin');
    ownerCodes = await PasswordRecoveryService.issueRecoveryCodes(client, 'owner-user');
    await client.query(
      `INSERT INTO sessions(id,user_id,company_id,refresh_token,expires_at)
       VALUES('old-session','owner-user','recovery-company','old-refresh-token',NOW()+INTERVAL '1 day')`,
    );
    await client.query('COMMIT');

    const registration = await request(app).post('/api/v1/auth/register').send({
      company_name: 'Registered Recovery Market', name: 'Registered Owner', email: 'registered@recovery.test',
      password: 'RegisterPass!789', phone: '05550000000', tax_number: '2222222222', city: 'İstanbul',
      district: 'Kadıköy', address: 'Test adresi', accept_terms: true, accept_privacy: true, accept_kvkk: true,
    });
    assert.equal(registration.status, 201, JSON.stringify(registration.body));
    assert.equal(registration.body.recovery_codes.length, 10, 'Registration must return exactly ten one-time recovery codes');
    const registeredUserId = registration.body.user_id || registration.body.user?.id;
    assert.ok(registeredUserId);
    const storedRegistrationCodes = await client.query(
      'SELECT code_hash FROM user_recovery_codes WHERE user_id=$1', [registeredUserId],
    );
    assert.equal(storedRegistrationCodes.rowCount, 10);
    assert.ok(storedRegistrationCodes.rows.every(row => !registration.body.recovery_codes.includes(row.code_hash)),
      'Recovery code plaintext must never be persisted');

    const wrongIdentity = await PasswordRecoveryService.recoverWithIdentityAndCode({
      identifier: 'owner@recovery.test', companyName: 'Wrong Company', taxNumber: '1234567890', recoveryCode: ownerCodes[0],
    });
    assert.equal(wrongIdentity, null, 'Wrong identity must not authorize recovery');

    const authorization = await PasswordRecoveryService.recoverWithIdentityAndCode({
      identifier: 'owner@recovery.test', companyName: 'Recovery Market', taxNumber: '1234567890', recoveryCode: ownerCodes[0],
    });
    assert.ok(authorization?.resetToken, 'Valid identity plus recovery code must authorize reset');

    const replayCode = await PasswordRecoveryService.recoverWithIdentityAndCode({
      identifier: 'owner@recovery.test', companyName: 'Recovery Market', taxNumber: '1234567890', recoveryCode: ownerCodes[0],
    });
    assert.equal(replayCode, null, 'Recovery code must be single-use');

    await assert.rejects(
      () => PasswordRecoveryService.resetPassword(authorization!.resetToken, 'OldPassword!123'),
      /password_reuse_not_allowed/,
    );
    const resetResults = await Promise.all([
      PasswordRecoveryService.resetPassword(authorization!.resetToken, 'NewPassword!456'),
      PasswordRecoveryService.resetPassword(authorization!.resetToken, 'NewPassword!456'),
    ]);
    assert.equal(resetResults.filter(Boolean).length, 1, 'Reset authorization must be consumed exactly once under concurrency');
    const owner = await client.query('SELECT password_hash,token_version FROM users WHERE id=$1', ['owner-user']);
    assert.equal((await AuthService.verifyPassword('NewPassword!456', owner.rows[0].password_hash)).valid, true);
    assert.ok(Number(owner.rows[0].token_version) >= 2, 'Token version must advance');
    assert.equal((await client.query("SELECT is_revoked FROM sessions WHERE id='old-session'")).rows[0].is_revoked, true);

    const legacyIdentity = await request(app).post('/api/v1/auth/verify-identity').send({
      email: 'owner@recovery.test', company_name: 'Recovery Market', tax_number: '1234567890',
    });
    assert.equal(legacyIdentity.status, 410, 'Identity-only legacy route must remain closed');
    const legacyEmail = await request(app).post('/api/v1/auth/forgot-password').send({ email: 'owner@recovery.test' });
    assert.equal(legacyEmail.status, 410, 'Email-only legacy route must remain closed');

    const httpAuthorization = await request(app).post('/api/v1/auth/recovery/authorize-code').send({
      identifier: 'owner@recovery.test', company_name: 'Recovery Market', tax_number: '1234567890', recovery_code: ownerCodes[1],
    });
    assert.equal(httpAuthorization.status, 200);
    assert.ok(httpAuthorization.body.reset_token);
    const weakPassword = await request(app).post('/api/v1/auth/reset-password').send({
      token: httpAuthorization.body.reset_token, newPassword: 'short',
    });
    assert.equal(weakPassword.status, 400);
    const httpReset = await request(app).post('/api/v1/auth/reset-password').send({
      token: httpAuthorization.body.reset_token, newPassword: 'HttpNewPass!789',
    });
    assert.equal(httpReset.status, 200);

    const employeeRequest = await PasswordRecoveryService.createAdminAssistedRequest({
      targetUserId: 'employee-user', actorId: 'owner-user', actorCompanyId: 'recovery-company', actorRoles: ['owner'],
      reason: 'Çalışan kimliği telefonla doğrulandı',
    });
    assert.ok(employeeRequest.claimCode && !employeeRequest.requiresSecondApproval);
    const employeeClaim = await PasswordRecoveryService.claimAdminRequest(employeeRequest.requestId, employeeRequest.claimCode!);
    assert.ok(employeeClaim?.resetToken);
    assert.equal(await PasswordRecoveryService.resetPassword(employeeClaim!.resetToken, 'EmployeeNew!456'), true);

    const blockedRequest = await PasswordRecoveryService.createAdminAssistedRequest({
      targetUserId: 'blocked-employee', actorId: 'owner-user', actorCompanyId: 'recovery-company', actorRoles: ['owner'],
      reason: 'Hatalı kod denemelerinin sınırlandırılması testi',
    });
    for (let attempt = 0; attempt < 5; attempt += 1) {
      assert.equal(await PasswordRecoveryService.claimAdminRequest(blockedRequest.requestId, 'WRONG-CODE'), null);
    }
    assert.equal(await PasswordRecoveryService.claimAdminRequest(blockedRequest.requestId, blockedRequest.claimCode!), null,
      'A request blocked after five failures must remain terminal');

    await assert.rejects(() => PasswordRecoveryService.createAdminAssistedRequest({
      targetUserId: 'other-owner', actorId: 'owner-user', actorCompanyId: 'recovery-company', actorRoles: ['owner'],
      reason: 'Başka şirket hesabına erişim denemesi',
    }), /forbidden/);
    await assert.rejects(() => PasswordRecoveryService.createAdminAssistedRequest({
      targetUserId: 'owner-user', actorId: 'owner-user', actorCompanyId: 'recovery-company', actorRoles: ['owner'],
      reason: 'Kendi hesabımı yönetici yoluyla sıfırlama',
    }), /self_admin_recovery_forbidden/);

    const sysadminRequest = await PasswordRecoveryService.createAdminAssistedRequest({
      targetUserId: 'sysadmin-target', actorId: 'sysadmin-a', actorCompanyId: 'serenut-admin', actorRoles: ['sysadmin'],
      reason: 'Platform yöneticisi erişim kurtarma talebi',
    });
    assert.equal(sysadminRequest.requiresSecondApproval, true);
    assert.equal(sysadminRequest.claimCode, undefined);
    await assert.rejects(
      () => PasswordRecoveryService.approveSysadminRequest(sysadminRequest.requestId, 'sysadmin-a'),
      /independent_approval_required/,
    );
    const approved = await PasswordRecoveryService.approveSysadminRequest(sysadminRequest.requestId, 'sysadmin-b');
    const adminClaim = await PasswordRecoveryService.claimAdminRequest(sysadminRequest.requestId, approved.claimCode);
    assert.ok(adminClaim?.resetToken);
    assert.equal(await PasswordRecoveryService.resetPassword(adminClaim!.resetToken, 'AdminNewPass!456'), true);

    const events = await client.query('SELECT event_type FROM password_security_events');
    assert.ok(events.rowCount && events.rowCount >= 8, 'Recovery lifecycle must be auditable');
    console.log('✅ Password recovery lifecycle, replay, concurrency, tenant and dual-approval tests passed.');
  } finally {
    client.release();
    await pgPool.end();
  }
}

run().then(() => process.exit(0)).catch(error => { console.error(error); process.exit(1); });

import crypto from 'crypto';
import { PoolClient } from 'pg';
import { pgPool } from '../../config/database';
import { AuthService } from './auth.service';

type RequestContext = { ip?: string; userAgent?: string };

const ACTIVE_STATES = "('requested','pending_second_approval','authorized')";
const RECOVERY_CODE_COUNT = 10;
const RESET_WINDOW_MINUTES = 15;
const CLAIM_WINDOW_MINUTES = 30;

function secret(): string {
  const value = process.env.PASSWORD_RECOVERY_SECRET || process.env.JWT_SECRET;
  if (!value || value.length < 32) throw new Error('password_recovery_secret_missing');
  return value;
}

function digest(value: string): string {
  return crypto.createHmac('sha256', secret()).update(value.trim().toUpperCase()).digest('hex');
}

function opaque(prefix: string): string {
  return `${prefix}-${crypto.randomUUID()}`;
}

function randomCode(): string {
  const raw = crypto.randomBytes(8).toString('hex').toUpperCase();
  return `SRNT-${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}`;
}

function randomClaimCode(): string {
  return crypto.randomBytes(5).toString('hex').toUpperCase();
}

export class PasswordRecoveryService {
  static isStrongPassword(value: string): boolean {
    return typeof value === 'string' && value.length >= 12 && /[a-z]/.test(value)
      && /[A-Z]/.test(value) && /\d/.test(value) && /[^A-Za-z0-9]/.test(value);
  }

  static async createInitialClaim(
    client: PoolClient,
    params: { targetUserId: string; companyId: string; actorId: string; reason: string; context?: RequestContext },
  ): Promise<{ requestId: string; claimCode: string }> {
    const requestId = opaque('prr');
    const claimCode = randomClaimCode();
    await client.query(
      `INSERT INTO password_recovery_requests
       (id,user_id,company_id,method,state,claim_code_hash,expires_at,initiated_by,reason,requested_ip,requested_user_agent)
       VALUES($1,$2,$3,'admin_assisted','requested',$4,NOW()+($5||' minutes')::interval,$6,$7,$8,$9)`,
      [requestId, params.targetUserId, params.companyId, digest(claimCode), CLAIM_WINDOW_MINUTES,
        params.actorId, params.reason, params.context?.ip || null, params.context?.userAgent || null],
    );
    await this.securityEvent(client, params.targetUserId, params.companyId, requestId,
      'INITIAL_PASSWORD_CLAIM_CREATED', params.actorId, params.context);
    return { requestId, claimCode };
  }

  static async issueRecoveryCodes(client: PoolClient, userId: string): Promise<string[]> {
    await client.query(
      `UPDATE user_recovery_codes SET revoked_at=NOW()
       WHERE user_id=$1 AND used_at IS NULL AND revoked_at IS NULL`,
      [userId],
    );
    const batchId = opaque('rcb');
    const codes = Array.from({ length: RECOVERY_CODE_COUNT }, () => randomCode());
    for (const code of codes) {
      await client.query(
        `INSERT INTO user_recovery_codes(id,user_id,batch_id,code_hash)
         VALUES($1,$2,$3,$4)`,
        [opaque('rcc'), userId, batchId, digest(code)],
      );
    }
    return codes;
  }

  static async recoverWithIdentityAndCode(params: {
    identifier: string;
    companyName: string;
    taxNumber: string;
    recoveryCode: string;
    context?: RequestContext;
  }): Promise<{ resetToken: string; expiresInSeconds: number } | null> {
    const identifier = params.identifier.trim().toLowerCase();
    const companyName = params.companyName.trim();
    const taxNumber = params.taxNumber.replace(/\D/g, '');
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls='true'");
      const user = await client.query(
        `SELECT u.id,u.company_id FROM users u JOIN companies c ON c.id=u.company_id
         WHERE (LOWER(u.email)=$1 OR LOWER(u.username)=$1)
           AND LOWER(c.name)=LOWER($2)
           AND REGEXP_REPLACE(c.tax_number,'\\D','','g')=$3
           AND u.is_active=TRUE AND u.deleted_at IS NULL
         FOR UPDATE OF u`,
        [identifier, companyName, taxNumber],
      );
      if (!user.rowCount) {
        await client.query('ROLLBACK');
        return null;
      }
      const target = user.rows[0];
      const code = await client.query(
        `SELECT id FROM user_recovery_codes
         WHERE user_id=$1 AND code_hash=$2 AND used_at IS NULL AND revoked_at IS NULL
         FOR UPDATE`,
        [target.id, digest(params.recoveryCode)],
      );
      if (!code.rowCount) {
        await this.securityEvent(client, target.id, target.company_id, null, 'RECOVERY_CODE_REJECTED', null, params.context);
        await client.query('COMMIT');
        return null;
      }
      await client.query(`UPDATE password_recovery_requests SET state='cancelled',updated_at=NOW() WHERE user_id=$1 AND state IN ${ACTIVE_STATES}`, [target.id]);
      const resetToken = crypto.randomBytes(32).toString('hex');
      const requestId = opaque('prr');
      await client.query(
        `INSERT INTO password_recovery_requests
         (id,user_id,company_id,method,state,authorization_hash,expires_at,requested_ip,requested_user_agent,authorized_at)
         VALUES($1,$2,$3,'recovery_code','authorized',$4,NOW()+($5||' minutes')::interval,$6,$7,NOW())`,
        [requestId, target.id, target.company_id, digest(resetToken), RESET_WINDOW_MINUTES,
          params.context?.ip || null, params.context?.userAgent || null],
      );
      await client.query('UPDATE user_recovery_codes SET used_at=NOW() WHERE id=$1', [code.rows[0].id]);
      await this.securityEvent(client, target.id, target.company_id, requestId, 'RECOVERY_AUTHORIZED', target.id, params.context, { method: 'recovery_code' });
      await client.query('COMMIT');
      return { resetToken, expiresInSeconds: RESET_WINDOW_MINUTES * 60 };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  static async resetPassword(resetToken: string, newPassword: string, context?: RequestContext): Promise<boolean> {
    if (!this.isStrongPassword(newPassword)) {
      throw new Error('weak_password');
    }
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls='true'");
      const request = await client.query(
        `SELECT pr.id,pr.user_id,pr.company_id,u.password_hash
         FROM password_recovery_requests pr JOIN users u ON u.id=pr.user_id
         WHERE pr.authorization_hash=$1 AND pr.state='authorized' AND pr.expires_at>NOW()
         FOR UPDATE OF pr,u`,
        [digest(resetToken)],
      );
      if (!request.rowCount) {
        await client.query('ROLLBACK');
        return false;
      }
      const row = request.rows[0];
      const same = await AuthService.verifyPassword(newPassword, row.password_hash);
      if (same.valid) throw new Error('password_reuse_not_allowed');
      const hash = await AuthService.hashPassword(newPassword);
      await client.query(
        `UPDATE users SET password_hash=$1,token_version=token_version+1,
         failed_login_attempts=0,locked_until=NULL,updated_at=NOW() WHERE id=$2`,
        [hash, row.user_id],
      );
      await client.query('UPDATE sessions SET is_revoked=TRUE,updated_at=NOW() WHERE user_id=$1', [row.user_id]);
      await client.query(
        `UPDATE password_recovery_requests SET state='consumed',consumed_at=NOW(),authorization_hash=NULL,updated_at=NOW()
         WHERE id=$1`,
        [row.id],
      );
      await client.query(
        `UPDATE password_recovery_requests SET state='cancelled',updated_at=NOW()
         WHERE user_id=$1 AND id<>$2 AND state IN ${ACTIVE_STATES}`,
        [row.user_id, row.id],
      );
      await this.securityEvent(client, row.user_id, row.company_id, row.id, 'PASSWORD_RESET_COMPLETED', row.user_id, context);
      await client.query('COMMIT');
      return true;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  static async createAdminAssistedRequest(params: {
    targetUserId: string; actorId: string; actorCompanyId: string; actorRoles: string[]; reason: string; context?: RequestContext;
  }): Promise<{ requestId: string; claimCode?: string; requiresSecondApproval: boolean }> {
    if (params.reason.trim().length < 10) throw new Error('recovery_reason_required');
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls='true'");
      const target = await client.query(
        `SELECT u.id,u.company_id,EXISTS(SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=u.id AND r.name='sysadmin') AS is_sysadmin
         FROM users u WHERE u.id=$1 AND u.is_active=TRUE AND u.deleted_at IS NULL FOR UPDATE`,
        [params.targetUserId],
      );
      if (!target.rowCount) throw new Error('user_not_found');
      const row = target.rows[0];
      const actorIsSysadmin = params.actorRoles.includes('sysadmin');
      if (!actorIsSysadmin && (row.company_id !== params.actorCompanyId || !params.actorRoles.some(role => ['owner','admin'].includes(role)))) {
        throw new Error('forbidden');
      }
      if (row.is_sysadmin && !actorIsSysadmin) throw new Error('forbidden');
      if (row.id === params.actorId) throw new Error('self_admin_recovery_forbidden');
      await client.query(`UPDATE password_recovery_requests SET state='cancelled',updated_at=NOW() WHERE user_id=$1 AND state IN ${ACTIVE_STATES}`, [row.id]);
      const requestId = opaque('prr');
      const requiresSecondApproval = Boolean(row.is_sysadmin);
      const claimCode = requiresSecondApproval ? undefined : randomClaimCode();
      await client.query(
        `INSERT INTO password_recovery_requests
         (id,user_id,company_id,method,state,claim_code_hash,expires_at,initiated_by,reason,requested_ip,requested_user_agent)
         VALUES($1,$2,$3,'admin_assisted',$4,$5,NOW()+($6||' minutes')::interval,$7,$8,$9,$10)`,
        [requestId, row.id, row.company_id, requiresSecondApproval ? 'pending_second_approval' : 'requested',
          claimCode ? digest(claimCode) : null, CLAIM_WINDOW_MINUTES, params.actorId, params.reason.trim(),
          params.context?.ip || null, params.context?.userAgent || null],
      );
      await this.securityEvent(client, row.id, row.company_id, requestId, 'ADMIN_RECOVERY_REQUESTED', params.actorId, params.context, { requiresSecondApproval });
      await client.query('COMMIT');
      return { requestId, claimCode, requiresSecondApproval };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally { client.release(); }
  }

  static async approveSysadminRequest(requestId: string, approverId: string, context?: RequestContext): Promise<{ claimCode: string }> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls='true'");
      const request = await client.query(
        `SELECT * FROM password_recovery_requests WHERE id=$1 AND state='pending_second_approval' AND expires_at>NOW() FOR UPDATE`,
        [requestId],
      );
      if (!request.rowCount) throw new Error('recovery_request_not_found');
      const row = request.rows[0];
      if (row.initiated_by === approverId || row.user_id === approverId) throw new Error('independent_approval_required');
      const approver = await client.query(
        `SELECT 1 FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id=$1 AND r.name='sysadmin'`,
        [approverId],
      );
      if (!approver.rowCount) throw new Error('forbidden');
      const claimCode = randomClaimCode();
      await client.query(
        `UPDATE password_recovery_requests SET state='requested',approved_by=$1,claim_code_hash=$2,updated_at=NOW() WHERE id=$3`,
        [approverId, digest(claimCode), requestId],
      );
      await this.securityEvent(client, row.user_id, row.company_id, requestId, 'ADMIN_RECOVERY_APPROVED', approverId, context);
      await client.query('COMMIT');
      return { claimCode };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally { client.release(); }
  }

  static async claimAdminRequest(requestId: string, claimCode: string, context?: RequestContext): Promise<{ resetToken: string; expiresInSeconds: number } | null> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls='true'");
      const request = await client.query(
        `SELECT * FROM password_recovery_requests WHERE id=$1 AND method='admin_assisted' AND state='requested' AND expires_at>NOW() FOR UPDATE`,
        [requestId],
      );
      if (!request.rowCount) { await client.query('ROLLBACK'); return null; }
      const row = request.rows[0];
      if (!row.claim_code_hash || !crypto.timingSafeEqual(Buffer.from(row.claim_code_hash), Buffer.from(digest(claimCode)))) {
        const attempts = Number(row.attempts) + 1;
        await client.query(`UPDATE password_recovery_requests SET attempts=$1,state=CASE WHEN $1>=5 THEN 'blocked' ELSE state END,updated_at=NOW() WHERE id=$2`, [attempts, requestId]);
        await client.query('COMMIT');
        return null;
      }
      const resetToken = crypto.randomBytes(32).toString('hex');
      await client.query(
        `UPDATE password_recovery_requests SET state='authorized',authorization_hash=$1,claim_code_hash=NULL,
         authorized_at=NOW(),expires_at=NOW()+($2||' minutes')::interval,updated_at=NOW() WHERE id=$3`,
        [digest(resetToken), RESET_WINDOW_MINUTES, requestId],
      );
      await this.securityEvent(client, row.user_id, row.company_id, requestId, 'ADMIN_RECOVERY_CLAIMED', row.user_id, context);
      await client.query('COMMIT');
      return { resetToken, expiresInSeconds: RESET_WINDOW_MINUTES * 60 };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally { client.release(); }
  }

  private static async securityEvent(client: PoolClient, userId: string, companyId: string, requestId: string | null,
    eventType: string, actorId: string | null, context?: RequestContext, metadata: Record<string, unknown> = {}): Promise<void> {
    await client.query(
      `INSERT INTO password_security_events(id,user_id,company_id,recovery_request_id,event_type,actor_id,ip_address,user_agent,metadata)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)`,
      [opaque('pse'), userId, companyId, requestId, eventType, actorId, context?.ip || null, context?.userAgent || null, JSON.stringify(metadata)],
    );
  }
}

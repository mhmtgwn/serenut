// server/src/modules/release_v2/services/release-fsm.service.ts
import { Pool } from 'pg';
import { ReleaseAuditService } from './release-audit.service';

export class ReleaseFsmService {
  private auditService: ReleaseAuditService;

  constructor(private pool: Pool) {
    this.auditService = new ReleaseAuditService(pool);
  }

  /**
   * Executes a state transition if all transition guards are satisfied.
   * Runs atomically in a single transaction.
   */
  async transition(
    releaseId: string,
    targetState: string,
    actorId: string
  ): Promise<{ success: boolean; error?: string }> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // 1. Fetch current release state
      const relRes = await client.query(
        'SELECT current_state, manifest_signature FROM releases WHERE release_id = $1',
        [releaseId]
      );
      if (relRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Release not found' };
      }

      const release = relRes.rows[0];
      const fromState = release.current_state;

      if (fromState === targetState) {
        await client.query('ROLLBACK');
        return { success: true }; // NOP transition
      }

      // 2. Fetch transition guard from database
      const guardRes = await client.query(
        'SELECT * FROM release_transition_guards WHERE from_state = $1 AND to_state = $2',
        [fromState, targetState]
      );

      if (guardRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return {
          success: false,
          error: `Illegal state transition from "${fromState}" to "${targetState}"`
        };
      }

      const guard = guardRes.rows[0];

      // 3. Verify Signature Guard
      if (guard.requires_signature && !release.manifest_signature) {
        await client.query('ROLLBACK');
        return {
          success: false,
          error: `Transition to "${targetState}" requires valid cryptographic signature.`
        };
      }

      // 4. Verify Canary Health Guard
      if (guard.requires_canary_health) {
        const healthRes = await client.query(
          'SELECT health_score FROM release_health_snapshots WHERE release_id = $1 ORDER BY created_at DESC LIMIT 1',
          [releaseId]
        );
        if (healthRes.rows.length === 0) {
          await client.query('ROLLBACK');
          return {
            success: false,
            error: `Transition to "${targetState}" requires active canary health snapshots.`
          };
        }
        const lastScore = parseFloat(healthRes.rows[0].health_score);
        if (lastScore < 0.95) {
          await client.query('ROLLBACK');
          return {
            success: false,
            error: `Canary health score too low: ${lastScore} (requires >= 0.95).`
          };
        }
      }

      // 5. Apply the transition
      await client.query(
        "UPDATE releases SET current_state = $1, updated_at = NOW() WHERE release_id = $2",
        [targetState, releaseId]
      );

      // 6. Log the transition to the immutable audit trail
      await this.auditService.log({
        releaseId,
        actorId,
        action: targetState === 'signed' ? 'SIGN' : targetState === 'canary' || targetState === 'stable' ? 'PROMOTE' : targetState === 'yanked' ? 'YANK' : 'PUBLISH',
        fromState,
        toState: targetState,
        payload: { transitionVerified: true, guardId: guard.id }
      });

      await client.query('COMMIT');
      return { success: true };
    } catch (err: any) {
      await client.query('ROLLBACK');
      return { success: false, error: err.message || String(err) };
    } finally {
      client.release();
    }
  }
}

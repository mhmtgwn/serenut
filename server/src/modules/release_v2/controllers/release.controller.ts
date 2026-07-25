// server/src/modules/release_v2/controllers/release.controller.ts
import { Router, Request, Response } from 'express';
import { pgPool } from '../../../config/database';
import { ReleaseRegistryService } from '../services/release-registry.service';
import { ReleaseFsmService } from '../services/release-fsm.service';
import { ReleaseAuditService } from '../services/release-audit.service';

const router = Router();
const registryService = new ReleaseRegistryService(pgPool);
const fsmService = new ReleaseFsmService(pgPool);
const auditService = new ReleaseAuditService(pgPool);

// 1. Atomic Release Publish
router.post('/publish', async (req: Request, res: Response) => {
  const { manifest, canonicalManifestJson, manifestSignature, buildCommit, buildPipelineId, actorId } = req.body;
  if (!manifest || !canonicalManifestJson || !manifestSignature || !buildCommit || !buildPipelineId || !actorId) {
    return res.status(400).json({ error: 'missing_parameters', message: 'All release parameters are required.' });
  }

  try {
    const result = await registryService.publishRelease(
      manifest,
      canonicalManifestJson,
      manifestSignature,
      buildCommit,
      buildPipelineId,
      actorId
    );

    if (!result.success) {
      return res.status(500).json({ error: 'publish_failed', message: result.error });
    }

    return res.json({
      success: true,
      releaseId: result.releaseId,
      artifactSetHash: result.artifactSetHash
    });
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

// 2. FSM Transition
router.post('/:id/transition', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { targetState, actorId } = req.body;

  if (!targetState || !actorId) {
    return res.status(400).json({ error: 'missing_parameters', message: 'targetState and actorId are required.' });
  }

  try {
    const result = await fsmService.transition(id, targetState, actorId);
    if (!result.success) {
      return res.status(400).json({ error: 'transition_failed', message: result.error });
    }

    return res.json({ success: true, message: `Transitioned successfully to ${targetState}` });
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

// 3. Get Latest Stable Release
router.get('/latest', async (req: Request, res: Response) => {
  try {
    // Query the latest stable release from registry manifest store
    const query = `
      SELECT store.canonical_manifest_json, store.manifest_signature
      FROM release_manifest_store store
      JOIN releases r ON r.release_id = store.release_id
      WHERE r.current_state = 'stable'
      ORDER BY r.created_at DESC
      LIMIT 1
    `;
    const result = await pgPool.query(query);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'no_stable_release', message: 'No stable release manifest found.' });
    }

    const { canonical_manifest_json, manifest_signature } = result.rows[0];
    const manifest = JSON.parse(canonical_manifest_json);

    return res.json({
      manifest,
      signature: manifest_signature
    });
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

// 4. Insert Health Snapshot
router.post('/:id/health-snapshot', async (req: Request, res: Response) => {
  const { id } = req.params;
  const { rolloutPercent, devices, successRate, rollbackRate, crashRate, healthScore } = req.body;

  if (rolloutPercent == null || devices == null || successRate == null || rollbackRate == null || crashRate == null || healthScore == null) {
    return res.status(400).json({ error: 'missing_parameters', message: 'All health parameters are required.' });
  }

  try {
    await pgPool.query(`
      INSERT INTO release_health_snapshots (release_id, rollout_percent, devices, success_rate, rollback_rate, crash_rate, health_score)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
    `, [id, rolloutPercent, devices, successRate, rollbackRate, crashRate, healthScore]);

    return res.json({ success: true });
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

// 5. Verify Audit Chain
router.get('/audit/verify', async (req: Request, res: Response) => {
  try {
    const result = await auditService.verifyAuditChain();
    return res.json(result);
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

export default router;

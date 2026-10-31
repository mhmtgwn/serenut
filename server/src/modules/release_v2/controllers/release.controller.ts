// server/src/modules/release_v2/controllers/release.controller.ts
import { Router, Request, Response } from 'express';
import { ReleaseRegistryService } from '../services/release-registry.service';
import { ReleaseFsmService } from '../services/release-fsm.service';
import { ReleaseAuditService } from '../services/release-audit.service';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../../middleware/auth.middleware';

const router = Router();
const registryService = new ReleaseRegistryService();
const fsmService = new ReleaseFsmService();
const auditService = new ReleaseAuditService();

// 1. Atomic Release Publish
router.post('/publish', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { manifest, canonicalManifestJson, manifestSignature, buildCommit, buildPipelineId } = req.body;
  if (!manifest || !canonicalManifestJson || !manifestSignature || !buildCommit || !buildPipelineId) {
    return res.status(400).json({ error: 'missing_parameters', message: 'All release parameters are required.' });
  }

  try {
    const result = await registryService.publishRelease(
      manifest,
      canonicalManifestJson,
      manifestSignature,
      buildCommit,
      buildPipelineId,
      req.user!.id
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
router.post('/:id/transition', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const { targetState } = req.body;

  if (!targetState) {
    return res.status(400).json({ error: 'missing_parameters', message: 'targetState is required.' });
  }

  try {
    const result = await fsmService.transition(id, targetState, req.user!.id);
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
    const row = await registryService.getLatestStableManifest();

    if (!row) {
      return res.status(404).json({ error: 'no_stable_release', message: 'No stable release manifest found.' });
    }

    const { canonical_manifest_json, manifest_signature } = row;
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
router.post('/:id/health-snapshot', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const { rolloutPercent, devices, successRate, rollbackRate, crashRate, healthScore } = req.body;

  if (rolloutPercent == null || devices == null || successRate == null || rollbackRate == null || crashRate == null || healthScore == null) {
    return res.status(400).json({ error: 'missing_parameters', message: 'All health parameters are required.' });
  }

  try {
    await registryService.insertHealthSnapshot({
      releaseId: id,
      rolloutPercent,
      devices,
      successRate,
      rollbackRate,
      crashRate,
      healthScore,
    });

    return res.json({ success: true });
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

// 5. Verify Audit Chain
router.get('/audit/verify', authenticateUser, requireRole('sysadmin'), async (_req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await auditService.verifyAuditChain();
    return res.json(result);
  } catch (err: any) {
    return res.status(500).json({ error: 'server_error', message: err.message || String(err) });
  }
});

export default router;

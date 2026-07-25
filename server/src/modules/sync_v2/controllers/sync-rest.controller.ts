import { Request, Response } from 'express';
import { logger } from '../../../config/logger';
import { RevisionService } from '../services/revision-service';
import { DeltaBuilderService } from '../services/delta-builder';
import { SnapshotBuilderService } from '../services/snapshot-builder';

export class SyncRestController {
  /**
   * POST /api/v2/sync/push
   * Pushes a batch of mutations from an offline client outbox.
   */
  public static async pushMutations(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const tenant_id = user?.company_id || req.body.tenant_id;
      const device_id = req.headers['x-device-id'] as string || req.body.device_id;

      if (!tenant_id || !device_id) {
        res.status(400).json({ error: 'Missing tenant_id or x-device-id header' });
        return;
      }

      const { mutations } = req.body;
      if (!Array.isArray(mutations)) {
        res.status(400).json({ error: 'Payload body must contain mutations array' });
        return;
      }

      const { results, head_vectors } = await RevisionService.processMutationsBatch(
        tenant_id,
        device_id,
        mutations
      );

      res.status(200).json({
        success: true,
        tenant_id,
        head_vectors,
        results,
      });
    } catch (err: any) {
      logger.error(`SyncRestController pushMutations error: ${err.message}`);
      res.status(500).json({ error: err.message || 'Internal Server Error' });
    }
  }

  /**
   * POST /api/v2/sync/delta
   * Vector-based smart delta pull.
   */
  public static async pullDelta(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const tenant_id = user?.company_id || req.body.tenant_id;

      if (!tenant_id) {
        res.status(400).json({ error: 'Missing tenant_id' });
        return;
      }

      const client_vectors = req.body.client_vectors || {};
      const max_batch_size = parseInt(req.body.max_batch_size || '500', 10);

      const deltaResult = await DeltaBuilderService.fetchDeltas(
        tenant_id,
        client_vectors,
        max_batch_size
      );

      res.status(200).json({
        success: true,
        tenant_id,
        ...deltaResult,
      });
    } catch (err: any) {
      logger.error(`SyncRestController pullDelta error: ${err.message}`);
      res.status(500).json({ error: err.message || 'Internal Server Error' });
    }
  }

  /**
   * GET /api/v2/sync/snapshot
   * Fetches latest base snapshot for full state hydration.
   */
  public static async getSnapshot(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const tenant_id = user?.company_id || (req.query.tenant_id as string);
      const domain = (req.query.domain as string) || 'sales';

      if (!tenant_id || !domain) {
        res.status(400).json({ error: 'Missing tenant_id or domain query param' });
        return;
      }

      let snapshot = await SnapshotBuilderService.getLatestSnapshot(tenant_id, domain);
      if (!snapshot) {
        // Trigger creation of fresh snapshot on demand if none exists
        snapshot = await SnapshotBuilderService.createSnapshot(tenant_id, domain);
      }

      res.status(200).json({
        success: true,
        snapshot,
      });
    } catch (err: any) {
      logger.error(`SyncRestController getSnapshot error: ${err.message}`);
      res.status(500).json({ error: err.message || 'Internal Server Error' });
    }
  }
}

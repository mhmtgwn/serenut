// server/src/modules/sync_v4/sync-v4.reset.routes.ts
import { Router } from "express";
import { requirePermission } from "../../middleware/auth.middleware";
import {
  requireDestructiveResetRole,
} from "./sync-v4.common";
import { syncV4ResetService } from "./sync-v4.reset.service";

const router = Router();

router.post(
  "/catalog-reset",
  requirePermission("settings:recovery") as any,
  requireDestructiveResetRole as any,
  async (req, res) => {
    const user = (req as any).user;
    const activationId = req.header("x-device-activation-id") || req.body?.device_activation_id;
    const deviceId = req.header("x-device-id") || req.body?.device_id;
    try {
      const result = await syncV4ResetService.performCatalogReset({
        companyId: user.company_id,
        userId: user.id,
        activationId,
        deviceId,
        ip: req.ip ?? null,
        correlationId: req.headers["x-correlation-id"] as string | undefined,
      });
      return res.json({ success: true, ...result });
    } catch (error: any) {
      const status = error?.message === "invalid_device_activation" ? 403 : 500;
      return res.status(status).json({ error: error?.message || "catalog_reset_failed" });
    }
  },
);

router.post(
  "/operational-reset",
  requirePermission("settings:recovery") as any,
  requireDestructiveResetRole as any,
  async (req, res) => {
    const user = (req as any).user;
    const activationId = req.header("x-device-activation-id") || req.body?.device_activation_id;
    const deviceId = req.header("x-device-id") || req.body?.device_id;
    try {
      const result = await syncV4ResetService.performOperationalReset({
        companyId: user.company_id,
        userId: user.id,
        activationId,
        deviceId,
        ip: req.ip ?? null,
        correlationId: req.headers["x-correlation-id"] as string | undefined,
      });
      return res.json({ success: true, ...result });
    } catch (error: any) {
      const status = error?.message === "invalid_device_activation" ? 403 : 500;
      return res.status(status).json({ error: error?.message || "operational_reset_failed" });
    }
  },
);

export default router;

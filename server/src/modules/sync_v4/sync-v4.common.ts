import type { PoolClient } from "pg";
import { pgPool } from "../../config/database";

export const requireDestructiveResetRole = (req: any, res: any, next: any) => {
  const roles = Array.isArray(req.user?.roles) ? req.user.roles : [];
  if (!roles.includes("owner") && !roles.includes("sysadmin")) {
    return res.status(403).json({
      error: "forbidden",
      message: "Bu işlem yalnızca işletme sahibi tarafından yapılabilir.",
    });
  }
  return next();
};

export async function assertActiveSyncActivation(
  companyId: string,
  activationId: unknown,
  installationId: unknown,
  executor: Pick<PoolClient, "query"> = pgPool,
): Promise<void> {
  if (typeof installationId !== "string" || !installationId) {
    throw new Error("invalid_device_activation");
  }
  // activationId is optional for trial users who haven't completed license activation yet.
  if (typeof activationId === "string" && activationId) {
    const activation = await executor.query(
      `SELECT id FROM device_activations
       WHERE id = $1 AND company_id = $2 AND device_hash = $3 AND status = 'active'`,
      [activationId, companyId, installationId],
    );
    if (activation.rowCount === 0) throw new Error("invalid_device_activation");
  } else {
    const activation = await executor.query(
      `SELECT id FROM device_activations
       WHERE company_id = $1 AND device_hash = $2 AND status = 'active'
       LIMIT 1`,
      [companyId, installationId],
    );
    if (activation.rowCount === 0) throw new Error("invalid_device_activation");
  }
}

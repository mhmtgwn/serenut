import { Router } from "express";
import { requirePermission } from "../../middleware/auth.middleware";
import { pgPool } from "../../config/database";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";
import { logger } from "../../config/logger";
import { stringValue } from "./sync-v4.materializer";
import { assertActiveSyncActivation } from "./sync-v4.common";

const router = Router();

const sharedHardwareTypes = new Set([
  "receiptPrinter", "labelPrinter", "scale", "paymentTerminal",
  "barcodeScanner", "customerDisplay",
]);
const sharedPrintOperations = new Set([
  "printReceipt", "printProductLabel", "printOrderLabel", "testPrint",
]);

const requireSharedHardwareEnabled = async (_req: any, res: any, next: any) => {
  try {
    const result = await pgPool.query(
      `SELECT COALESCE((value->>'shared_hardware_enabled')::boolean,true) AS enabled
       FROM remote_configs WHERE key='global_config' LIMIT 1`,
    );
    if (result.rows[0]?.enabled === false) {
      return res.status(503).json({ error: "shared_hardware_temporarily_disabled" });
    }
    next();
  } catch (error) {
    next(error);
  }
};

router.use("/shared-hardware", requireSharedHardwareEnabled);
router.use("/hardware-jobs", requireSharedHardwareEnabled);

function safeHardwareObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const source = value as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(source)) {
    if (/password|secret|api[_-]?key|pin|token/i.test(key)) continue;
    if (["string", "number", "boolean"].includes(typeof item) || item === null) {
      result[key] = item;
    }
  }
  return result;
}

router.post("/device-hardware-profile/restore", async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `SELECT profile, updated_at FROM device_hardware_profiles
       WHERE device_activation_id = $1 AND company_id = $2`,
      [activationId, user.company_id],
    );
    await client.query("COMMIT");
    return res.json({
      profile: result.rows[0]?.profile ?? [],
      updated_at: result.rows[0]?.updated_at ?? null,
    });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "profile_restore_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500)
      .json({ error: message });
  } finally {
    client.release();
  }
});

router.put("/device-hardware-profile", async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const profile = req.body?.profile;
  if (!Array.isArray(profile) || profile.length > 20) {
    return res.status(400).json({ error: "invalid_hardware_profile" });
  }
  const encoded = JSON.stringify(profile);
  if (encoded.length > 64_000 || /password|secret|api[_-]?key|pin/i.test(encoded)) {
    return res.status(400).json({ error: "unsafe_hardware_profile" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    await client.query(
      `INSERT INTO device_hardware_profiles
         (device_activation_id, company_id, profile, updated_at)
       VALUES ($1, $2, $3::jsonb, NOW())
       ON CONFLICT (device_activation_id) DO UPDATE
       SET profile = EXCLUDED.profile, updated_at = NOW()
       WHERE device_hardware_profiles.company_id = EXCLUDED.company_id`,
      [activationId, user.company_id, encoded],
    );
    await client.query("COMMIT");
    return res.json({ success: true });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "profile_save_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500)
      .json({ error: message });
  } finally {
    client.release();
  }
});

// Registers only hardware physically owned by this activated installation.
// The cloud id is namespaced so legacy local ids cannot collide across tenants.
router.put("/shared-hardware/presence", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const hardware = req.body?.hardware;
  if (!Array.isArray(hardware) || hardware.length > 50) {
    return res.status(400).json({ error: "invalid_shared_hardware" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const retainedIds: string[] = [];
    for (const raw of hardware) {
      if (!raw || typeof raw !== "object") throw new Error("invalid_shared_hardware");
      const item = raw as Record<string, unknown>;
      const localId = stringValue(item, "id");
      const name = stringValue(item, "name");
      const hardwareType = stringValue(item, "type");
      const connectionType = stringValue(item, "connection_type");
      if (!localId || localId.length > 180 || !name || name.length > 160 ||
          !sharedHardwareTypes.has(hardwareType) || !connectionType) {
        throw new Error("invalid_shared_hardware");
      }
      const cloudId = `${activationId}:${localId}`;
      retainedIds.push(cloudId);
      const configuration = safeHardwareObject(item.configuration);
      const capabilities = safeHardwareObject(item.capabilities);
      await client.query(
        `INSERT INTO shared_hardware
          (id,company_id,owner_activation_id,owner_device_id,name,hardware_type,
           connection_type,language,configuration,capabilities,sharing_scope,enabled,online,last_seen_at,updated_at)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11,$12,true,NOW(),NOW())
         ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name, hardware_type=EXCLUDED.hardware_type,
           connection_type=EXCLUDED.connection_type, language=EXCLUDED.language,
           configuration=EXCLUDED.configuration, capabilities=EXCLUDED.capabilities,
           sharing_scope=EXCLUDED.sharing_scope, enabled=EXCLUDED.enabled,
           online=true,last_seen_at=NOW(),updated_at=NOW()
         WHERE shared_hardware.company_id=EXCLUDED.company_id
           AND shared_hardware.owner_activation_id=EXCLUDED.owner_activation_id`,
        [cloudId,user.company_id,activationId,deviceId,name,hardwareType,connectionType,
          stringValue(item,"language") || null,JSON.stringify(configuration),JSON.stringify(capabilities),
          ["owner","branch","company"].includes(stringValue(item,"sharing_scope"))
            ? stringValue(item,"sharing_scope") : "company",
          item.enabled !== false],
      );
    }
    await client.query(
      `UPDATE shared_hardware SET online=false,updated_at=NOW()
       WHERE company_id=$1 AND owner_activation_id=$2
         AND NOT (id = ANY($3::text[]))`,
      [user.company_id, activationId, retainedIds],
    );
    await client.query("COMMIT");
    return res.json({ success: true, registered: retainedIds.length });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "shared_hardware_presence_failed";
    return res.status(message === "invalid_device_activation" ? 403 : message === "invalid_shared_hardware" ? 400 : 500)
      .json({ error: message });
  } finally { client.release(); }
});

router.post("/shared-hardware/list", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `SELECT h.id,h.name,h.hardware_type AS type,h.connection_type,h.language,h.capabilities,
              h.sharing_scope,h.enabled,
              (h.online=true AND a.status='active' AND
               a.last_seen_at > NOW()-INTERVAL '5 minutes') AS online,
              COALESCE(a.last_seen_at,h.last_seen_at) AS last_seen_at,
              h.owner_activation_id,h.owner_device_id,(h.owner_activation_id=$2) AS is_local
       FROM shared_hardware h
       JOIN device_activations a ON a.id=h.owner_activation_id AND a.company_id=h.company_id
       WHERE h.company_id=$1 AND h.enabled=true
         AND (h.sharing_scope='company' OR h.owner_activation_id=$2)
       ORDER BY online DESC,h.name ASC`,
      [user.company_id, activationId],
    );
    await client.query("COMMIT");
    return res.json({ hardware: result.rows });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "shared_hardware_list_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const hardwareId = req.body?.hardware_id;
  const operation = req.body?.operation;
  const payload = req.body?.payload;
  const idempotencyKey = req.header("idempotency-key") || req.body?.idempotency_key;
  const encodedPayload = JSON.stringify(payload ?? null);
  if (typeof hardwareId !== "string" || typeof operation !== "string" ||
      !sharedPrintOperations.has(operation) || typeof idempotencyKey !== "string" ||
      !payload || typeof payload !== "object" || encodedPayload.length > 512_000) {
    return res.status(400).json({ error: "invalid_hardware_job" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const target = await client.query(
      `SELECT owner_activation_id,hardware_type,enabled,sharing_scope FROM shared_hardware
       WHERE id=$1 AND company_id=$2 FOR SHARE`, [hardwareId,user.company_id]);
    if (!target.rowCount || !target.rows[0].enabled || target.rows[0].sharing_scope === "owner") {
      throw new Error("hardware_not_available");
    }
    const expectedType = operation === "printReceipt" ? "receiptPrinter" : "labelPrinter";
    if (operation !== "testPrint" && target.rows[0].hardware_type !== expectedType) {
      throw new Error("hardware_incompatible");
    }
    const result = await client.query(
      `INSERT INTO hardware_jobs
        (id,company_id,hardware_id,owner_activation_id,requested_by_activation_id,
         requested_by_user_id,operation,payload,idempotency_key)
       VALUES(gen_random_uuid(),$1,$2,$3,$4,$5,$6,$7::jsonb,$8)
       ON CONFLICT(company_id,idempotency_key) DO UPDATE SET updated_at=hardware_jobs.updated_at
       RETURNING id,state,created_at`,
      [user.company_id,hardwareId,target.rows[0].owner_activation_id,activationId,user.id,
        operation,encodedPayload,idempotencyKey.substring(0,180)],
    );
    await client.query("COMMIT");
    try {
      await RealtimeBroadcastService.publishEvent(
        user.company_id,
        "HardwareJobCreated",
        {
          job_id: result.rows[0].id,
          hardware_id: hardwareId,
          owner_activation_id: target.rows[0].owner_activation_id,
        },
      );
    } catch (e: any) {
      logger.warn("Failed to publish HardwareJobCreated realtime event", { error: e?.message });
    }
    return res.status(202).json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_create_failed";
    const status = message === "invalid_device_activation" ? 403 :
      ["hardware_not_available","hardware_incompatible"].includes(message) ? 409 : 500;
    return res.status(status).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/claim", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    await client.query(
      `UPDATE hardware_jobs SET state='requires_confirmation',lease_owner=NULL,
         lease_expires_at=NULL,error_code='owner_interrupted_during_delivery',
         error_message='Sahip cihaz yazdırma sırasında kapandı; çift baskıyı önlemek için otomatik tekrar durduruldu.',
         updated_at=NOW(),completed_at=NOW()
       WHERE company_id=$1 AND owner_activation_id=$2 AND state='executing'
         AND lease_expires_at<NOW()`,
      [user.company_id, activationId],
    );
    const result = await client.query(
      `WITH candidate AS (
         SELECT id FROM hardware_jobs
         WHERE company_id=$1 AND owner_activation_id=$2
           AND (state='queued' OR (state='retry_wait' AND next_attempt_at<=NOW())
                OR (state='claimed' AND lease_expires_at<NOW()))
           AND attempt_count<5
         ORDER BY created_at ASC FOR UPDATE SKIP LOCKED LIMIT 1
       )
       UPDATE hardware_jobs j SET state='claimed',attempt_count=attempt_count+1,
         lease_owner=$3,lease_expires_at=NOW()+INTERVAL '45 seconds',updated_at=NOW()
       FROM candidate WHERE j.id=candidate.id
       RETURNING j.id,j.hardware_id,j.operation,j.payload,j.attempt_count,j.lease_expires_at`,
      [user.company_id,activationId,deviceId],
    );
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] ?? null });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_claim_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/:id/start", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `UPDATE hardware_jobs SET state='executing',updated_at=NOW(),
         lease_expires_at=NOW()+INTERVAL '45 seconds'
       WHERE id=$1 AND company_id=$2 AND owner_activation_id=$3
         AND lease_owner=$4 AND state='claimed' AND lease_expires_at>NOW()
       RETURNING id,state`,
      [req.params.id,user.company_id,activationId,deviceId],
    );
    if (!result.rowCount) throw new Error("hardware_job_lease_lost");
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_start_failed";
    return res.status(message === "invalid_device_activation" ? 403 : message === "hardware_job_lease_lost" ? 409 : 500)
      .json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/list", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `SELECT j.id,j.hardware_id,h.name AS hardware_name,j.operation,j.state,
              j.attempt_count,j.error_code,j.error_message,j.created_at,j.updated_at,
              j.completed_at,(j.requested_by_activation_id=$2) AS requested_here,
              (j.owner_activation_id=$2) AS executed_here
       FROM hardware_jobs j JOIN shared_hardware h ON h.id=j.hardware_id
       WHERE j.company_id=$1 AND
         (j.requested_by_activation_id=$2 OR j.owner_activation_id=$2)
       ORDER BY j.created_at DESC LIMIT 200`,
      [user.company_id, activationId],
    );
    await client.query("COMMIT");
    return res.json({ jobs: result.rows });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_list_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/:id/action", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const action = req.body?.action;
  if (!["retry","cancel","confirmPrinted","confirmNotPrinted"].includes(action)) {
    return res.status(400).json({ error: "invalid_hardware_job_action" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const current = await client.query(
      `SELECT state FROM hardware_jobs WHERE id=$1 AND company_id=$2
         AND (requested_by_activation_id=$3 OR owner_activation_id=$3) FOR UPDATE`,
      [req.params.id,user.company_id,activationId],
    );
    if (!current.rowCount) throw new Error("hardware_job_not_found");
    const state = current.rows[0].state as string;
    let nextState: string;
    if (action === "retry" && ["failed"].includes(state)) nextState = "queued";
    else if (action === "cancel" && ["queued","retry_wait","failed"].includes(state)) nextState = "cancelled";
    else if (action === "confirmPrinted" && state === "requires_confirmation") nextState = "succeeded";
    else if (action === "confirmNotPrinted" && state === "requires_confirmation") nextState = "queued";
    else throw new Error("invalid_hardware_job_transition");
    const result = await client.query(
      `UPDATE hardware_jobs SET state=$1::varchar,attempt_count=CASE WHEN $1::varchar='queued' THEN 0 ELSE attempt_count END,
         lease_owner=NULL,lease_expires_at=NULL,next_attempt_at=NULL,
         error_code=NULL,error_message=NULL,updated_at=NOW(),
         completed_at=CASE WHEN $1::varchar IN ('succeeded','cancelled') THEN NOW() ELSE NULL END
       WHERE id=$2 AND company_id=$3 RETURNING id,state`,
      [nextState,req.params.id,user.company_id],
    );
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_action_failed";
    const status = message === "invalid_device_activation" ? 403 :
      message === "hardware_job_not_found" ? 404 :
      message === "invalid_hardware_job_transition" ? 409 : 500;
    return res.status(status).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/:id/result", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const state = req.body?.state;
  if (!["succeeded","failed","requires_confirmation","retry_wait"].includes(state)) {
    return res.status(400).json({ error: "invalid_hardware_job_result" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `UPDATE hardware_jobs SET state=$1::varchar,result=$2::jsonb,error_code=$3,error_message=$4,
         next_attempt_at=CASE WHEN $1::varchar='retry_wait' THEN NOW()+INTERVAL '10 seconds' ELSE NULL END,
         lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW(),
         completed_at=CASE WHEN $1::varchar IN ('succeeded','failed','requires_confirmation') THEN NOW() ELSE NULL END
       WHERE id=$5 AND company_id=$6 AND owner_activation_id=$7 AND lease_owner=$8
       RETURNING id,state`,
      [state,JSON.stringify(req.body?.result ?? {}),req.body?.error_code ?? null,
        String(req.body?.error_message ?? "").substring(0,500) || null,req.params.id,
        user.company_id,activationId,deviceId],
    );
    if (!result.rowCount) throw new Error("hardware_job_lease_lost");
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_result_failed";
    return res.status(message === "invalid_device_activation" ? 403 : message === "hardware_job_lease_lost" ? 409 : 500)
      .json({ error: message });
  } finally { client.release(); }
});

export default router;

import assert from "assert";
import fs from "fs";
import path from "path";

async function runPhase6Tests() {
  console.log("=== Phase 6 Test: Web Portalı & UI Uyumsuzlukları ===");

  // 1. Verify device-image:// normalization in sync-v4.materializer.ts
  const materializerPath = path.resolve(__dirname, "../modules/sync_v4/sync-v4.materializer.ts");
  const materializerContent = fs.readFileSync(materializerPath, "utf-8");

  assert.ok(
    materializerContent.includes('imagePath.startsWith("device-image://")') &&
    materializerContent.includes('`/uploads/product-images/${fileName}`'),
    "FAIL: sync-v4.materializer.ts should normalize device-image:// to /uploads/product-images/"
  );
  console.log("✔ 1. P2P device-image:// to web /uploads/product-images/ normalization verified");

  // 2. Verify admin dashboard queries use live production tables
  const adminControllerPath = path.resolve(__dirname, "../modules/admin/admin.controller.ts");
  const adminContent = fs.readFileSync(adminControllerPath, "utf-8");

  assert.ok(
    adminContent.includes("SELECT COUNT(*) FROM device_activations WHERE status = 'active'"),
    "FAIL: admin.controller.ts should query device_activations instead of dead devices table"
  );
  assert.ok(
    adminContent.includes("SELECT COUNT(*) FROM license_entitlements WHERE status IN ('active', 'trial')"),
    "FAIL: admin.controller.ts should query license_entitlements instead of dead licenses table"
  );
  assert.ok(
    adminContent.includes("SELECT COUNT(*) FROM sync_v4_changes WHERE created_at >= NOW() - INTERVAL '24 hours'"),
    "FAIL: admin.controller.ts should query sync_v4_changes instead of dead sync_queue table"
  );
  console.log("✔ 2. Admin dashboard live table metrics (device_activations, license_entitlements, sync_v4_changes) verified");

  // 3. Verify admin sync/monitor uses sync_v4_changes
  assert.ok(
    adminContent.includes("SELECT COUNT(*) FROM sync_v4_changes") &&
    adminContent.includes("FROM sync_v4_changes sc") &&
    !adminContent.includes("FROM sync_queue sq"),
    "FAIL: /sync/monitor should query sync_v4_changes and not dead sync_queue"
  );
  console.log("✔ 3. Admin /sync/monitor live pipeline queries verified");

  // 4. Verify crash-logs joins with device_activations
  assert.ok(
    adminContent.includes("LEFT JOIN device_activations d ON cl.device_id = d.device_id"),
    "FAIL: crash-logs should join with device_activations instead of devices"
  );
  console.log("✔ 4. Crash-logs device_activations relationship verified");

  // 5. Verify api-client.js handles 402 entitlement/payment required refresh
  const apiClientPath = path.resolve(__dirname, "../../public/shared/js/api-client.js");
  const apiClientContent = fs.readFileSync(apiClientPath, "utf-8");

  assert.ok(
    apiClientContent.includes("response.status === 401 || response.status === 402"),
    "FAIL: api-client.js should attempt refreshAccessToken on HTTP 402 as well as 401"
  );
  console.log("✔ 5. Web client 402 entitlement renewal retry verified");

  console.log("\nALL PHASE 6 TESTS PASSED! (5/5) 🎉");
}

runPhase6Tests().catch((err) => {
  console.error("Phase 6 Test Failed:", err);
  process.exit(1);
});

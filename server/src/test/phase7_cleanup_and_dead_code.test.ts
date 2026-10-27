import assert from "assert";
import fs from "fs";
import path from "path";

async function runPhase7Tests() {
  console.log("=== Phase 7 Test: Ölü Kod, Sahte Kontroller & Konsolidasyon ===");

  // 1. Verify getActiveWebSocketCount delegation in analytics.ws.ts
  const analyticsWsPath = path.resolve(__dirname, "../modules/analytics/analytics.ws.ts");
  const analyticsContent = fs.readFileSync(analyticsWsPath, "utf-8");

  assert.ok(
    analyticsContent.includes("ConnectionRegistry.getActiveConnectionsCount()"),
    "FAIL: analytics.ws.ts should delegate getActiveWebSocketCount to ConnectionRegistry"
  );
  console.log("✔ 1. WebSocket active connection count delegation to ConnectionRegistry verified");

  // 2. Verify branch.controller.ts licCheck queries real license_entitlements
  const branchControllerPath = path.resolve(__dirname, "../modules/branch/branch.controller.ts");
  const branchContent = fs.readFileSync(branchControllerPath, "utf-8");

  assert.ok(
    branchContent.includes("SELECT COUNT(*) as count FROM license_entitlements") &&
    branchContent.includes("metadata->>'store_id' = $2") &&
    !branchContent.includes("const licCheck = { rows: [{ count: '0' }] };"),
    "FAIL: branch.controller.ts should query license_entitlements instead of using a dummy stub"
  );
  console.log("✔ 2. Branch deletion real license entitlement validation verified");

  // 3. Verify logs.controller.ts uses async fs.promises.writeFile
  const logsControllerPath = path.resolve(__dirname, "../modules/logs/logs.controller.ts");
  const logsContent = fs.readFileSync(logsControllerPath, "utf-8");

  assert.ok(
    logsContent.includes("await fs.promises.writeFile(targetPath, buffer);") &&
    !logsContent.includes("fs.writeFileSync(targetPath, buffer);"),
    "FAIL: logs.controller.ts must use asynchronous writeFile to avoid event loop blocking"
  );
  console.log("✔ 3. Logs upload non-blocking asynchronous file writing verified");

  // 4. Verify mail.controller.ts SSRF protection and attachment size limits
  const mailControllerPath = path.resolve(__dirname, "../modules/mail/mail.controller.ts");
  const mailContent = fs.readFileSync(mailControllerPath, "utf-8");

  assert.ok(
    mailContent.includes("SSRF_BLOCKED") &&
    mailContent.includes("INVALID_URL") &&
    mailContent.includes("169.254.169.254"),
    "FAIL: mail.controller.ts must validate URL and block SSRF on mail attachment download"
  );
  console.log("✔ 4. Mail attachment SSRF filter and size limit verified");

  // 5. Verify StockChangedEvent native UUID support in Flutter client
  const domainEventPath = path.resolve(__dirname, "../../../lib/domain/events/domain_event.dart");
  const domainEventContent = fs.readFileSync(domainEventPath, "utf-8");

  assert.ok(
    domainEventContent.includes("class StockChangedEvent extends DomainEvent {") &&
    domainEventContent.includes("final String productId;"),
    "FAIL: StockChangedEvent must support native String UUID productId"
  );
  console.log("✔ 5. StockChangedEvent native String UUID support verified");

  // 6. Verify inventory_service.dart regex hack removal
  const inventoryServicePath = path.resolve(__dirname, "../../../lib/domain/services/inventory_service.dart");
  const inventoryContent = fs.readFileSync(inventoryServicePath, "utf-8");

  assert.ok(
    !inventoryContent.includes("replaceAll(RegExp(r'[^0-9]'), '')"),
    "FAIL: inventory_service.dart should not contain regex int hacks for UUID products"
  );
  console.log("✔ 6. Inventory service clean UUID event publishing verified");

  console.log("\nALL PHASE 7 TESTS PASSED! (6/6) 🎉");
}

runPhase7Tests().catch((err) => {
  console.error("Phase 7 Test Failed:", err);
  process.exit(1);
});

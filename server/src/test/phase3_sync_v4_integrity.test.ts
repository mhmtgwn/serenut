import * as fs from 'fs';
import * as path from 'path';

function runPhase3Tests() {
  console.log('--- Running Phase 3 Sync V4 and Offline Cash Integrity Tests ---');
  let passed = 0;
  let total = 0;

  function assert(condition: boolean, message: string) {
    total++;
    if (condition) {
      console.log(`✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`❌ FAIL: ${message}`);
    }
  }

  // 1. refund.service.ts fractional refund support (J1)
  const refundServicePath = path.resolve(__dirname, '../modules/order/refund.service.ts');
  const refundServiceContent = fs.readFileSync(refundServicePath, 'utf8');
  assert(
    !refundServiceContent.includes('!Number.isInteger(quantity)') &&
    refundServiceContent.includes('!Number.isFinite(quantity) || quantity <= 0'),
    'refund.service.ts permits fractional/weighted product quantities without Integer restriction'
  );

  // 2. sync-v4.materializer.ts catalog quantity overwrite prevention (H3, J10)
  const materializerPath = path.resolve(__dirname, '../modules/sync_v4/sync-v4.materializer.ts');
  const materializerContent = fs.readFileSync(materializerPath, 'utf8');
  assert(
    materializerContent.includes('quantity=products.quantity') &&
    !materializerContent.includes('quantity=EXCLUDED.quantity'),
    'sync-v4.materializer.ts protects product quantity from being overwritten by catalog sync'
  );

  // 3. sync-v4.routes.ts entityTypes set contains cash_expense and gib_invoice (J8, I4)
  const routesPath = path.resolve(__dirname, '../modules/sync_v4/sync-v4.routes.ts');
  const routesContent = fs.readFileSync(routesPath, 'utf8');
  assert(
    routesContent.includes('"cash_expense"') &&
    routesContent.includes('"gib_invoice"') &&
    routesContent.includes('"cash_count"'),
    'sync-v4.routes.ts whitelists cash_expense and gib_invoice entity types'
  );

  // 4. sync-v4.routes.ts push route allows pending mutation sync even when entitlement expired (F3)
  assert(
    routesContent.includes('req.path === "/push"') &&
    routesContent.includes('return next()'),
    'sync-v4.routes.ts keeps /push accessible for expired tenants to prevent local ledger data loss'
  );

  // 5. schema_v100.sql and schema_v101.sql exist and define RLS policies
  const schemaV100 = fs.readFileSync(path.resolve(__dirname, '../../db/schema_v100.sql'), 'utf8');
  const schemaV101 = fs.readFileSync(path.resolve(__dirname, '../../db/schema_v101.sql'), 'utf8');
  assert(
    schemaV100.includes('CREATE TABLE IF NOT EXISTS cash_expenses') &&
    schemaV100.includes('CREATE POLICY tenant_isolation ON cash_expenses') &&
    schemaV101.includes('CREATE TABLE IF NOT EXISTS gib_invoices') &&
    schemaV101.includes('CREATE POLICY tenant_isolation ON gib_invoices'),
    'schema_v100.sql and schema_v101.sql define cash_expenses and gib_invoices tables with RLS'
  );

  // 6. sync-v4.materializer.ts has upsertCashExpense and upsertGibInvoice
  assert(
    materializerContent.includes('export async function upsertCashExpense') &&
    materializerContent.includes('export async function upsertGibInvoice') &&
    materializerContent.includes('case "cash_expense":') &&
    materializerContent.includes('case "gib_invoice":'),
    'sync-v4.materializer.ts defines upsertCashExpense and upsertGibInvoice handlers'
  );

  // 7. Client end_of_day_repository.dart multi-terminal cash counts and expenses (J8, J9)
  const endOfDayRepoPath = path.resolve(__dirname, '../../../lib/infrastructure/repositories/end_of_day_repository.dart');
  const endOfDayRepoContent = fs.readFileSync(endOfDayRepoPath, 'utf8');
  assert(
    endOfDayRepoContent.includes('countId = (effectiveTerminalId != null') &&
    endOfDayRepoContent.includes("entityType: 'cash_count'") &&
    endOfDayRepoContent.includes("entityType: 'cash_expense'"),
    'end_of_day_repository.dart uses terminal-aware cash count IDs and syncs cash expenses'
  );

  // 8. Client sync_v4_service_recovery.dart and materializer (J7, J11)
  const recoveryPath = path.resolve(__dirname, '../../../lib/infrastructure/sync_v4/sync_v4_service_recovery.dart');
  const recoveryContent = fs.readFileSync(recoveryPath, 'utf8');
  assert(
    recoveryContent.includes("'customer_installment_plan': 6") &&
    recoveryContent.includes("'customer_installment': 7") &&
    recoveryContent.includes("'gib_invoice': 'gib_invoices'"),
    'sync_v4_service_recovery.dart orders installment plans before installments and tracks gib_invoice'
  );

  console.log(`\nResults: ${passed}/${total} assertions passed.`);
  if (passed !== total) {
    process.exit(1);
  }
}

runPhase3Tests();

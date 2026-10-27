import * as fs from 'fs';
import * as path from 'path';

function runPhase2Tests() {
  console.log('--- Running Phase 2 Financial Integrity Verification Tests ---');
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

  // 1. schema_v99.sql verification
  const schemaV99Path = path.resolve(__dirname, '../../db/schema_v99.sql');
  const schemaV99Content = fs.readFileSync(schemaV99Path, 'utf8');
  assert(
    schemaV99Content.includes("WHEN type IN ('sale', 'manual_debt')") &&
    schemaV99Content.includes("WHEN type IN ('payment', 'collection')") &&
    schemaV99Content.includes("WHEN type = 'cancellation'") &&
    schemaV99Content.includes("WHEN type = 'refund'"),
    'schema_v99.sql properly triggers balance updates for manual_debt, cancellation, and refund'
  );

  // 2. sync-v4.materializer.ts order routing verification
  const materializerPath = path.resolve(__dirname, '../modules/sync_v4/sync-v4.materializer.ts');
  const materializerContent = fs.readFileSync(materializerPath, 'utf8');
  assert(
    materializerContent.includes('reference_type === "order"') &&
    materializerContent.includes("customer_orders WHERE id=$1 AND company_id=$2 FOR UPDATE"),
    'sync-v4.materializer.ts routes order payment references directly to customer_orders table'
  );

  // 3. sync-v4.materializer.ts debt customer validation
  assert(
    materializerContent.includes('throw new Error("credit_sale_requires_customer")'),
    'sync-v4.materializer.ts rejects debt transactions without customer_id'
  );

  // 4. sales_service.dart debt validation
  const salesServicePath = path.resolve(__dirname, '../../../lib/domain/services/sales_service.dart');
  const salesServiceContent = fs.readFileSync(salesServicePath, 'utf8');
  assert(
    salesServiceContent.includes('Borç/veresiye kalan satışlar için müşteri seçilmesi zorunludur'),
    'sales_service.dart enforces customer selection for debt/veresiye transactions'
  );

  // 5. sales_page.dart cash tendered and change metadata
  const salesPagePath = path.resolve(__dirname, '../../../lib/presentation/pages/sales_page.dart');
  const salesPageContent = fs.readFileSync(salesPagePath, 'utf8');
  assert(
    salesPageContent.includes("'cash_tendered': flowState.paidAmount") &&
    salesPageContent.includes("'change': (flowState.paidAmount - totalAmount)"),
    'sales_page.dart persists cash_tendered and change in terminalMetadata for cash sales'
  );

  // 6. gib_earsiv_client.dart SMS verification exception
  const gibClientPath = path.resolve(__dirname, '../../../lib/infrastructure/services/gib_earsiv_client.dart');
  const gibClientContent = fs.readFileSync(gibClientPath, 'utf8');
  assert(
    gibClientContent.includes("throw GibInvoiceException(") &&
    gibClientContent.includes("GİB SMS onay yanıtı doğrulanamadı") &&
    !gibClientContent.slice(gibClientContent.indexOf('verifySmsCodeAndSignBatch')).includes("return true;\n  }"),
    'gib_earsiv_client.dart throws GibInvoiceException on ambiguous/unconfirmed SMS response'
  );

  console.log(`\nResults: ${passed}/${total} assertions passed.`);
  if (passed !== total) {
    process.exit(1);
  }
}

runPhase2Tests();

// server/src/test/sync_v2_verification.test.ts
// Phase 3 Verification Test Suite for Enterprise Sync Engine v2

import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { RevisionService } from '../modules/sync_v2/services/revision-service';
import { DeltaBuilderService } from '../modules/sync_v2/services/delta-builder';
import { SnapshotBuilderService } from '../modules/sync_v2/services/snapshot-builder';
import { TombstoneManagerService } from '../modules/sync_v2/services/tombstone-manager';
import { ConflictResolverDomain, MutationPayload } from '../modules/sync_v2/domain/conflict-resolver';
import { MutationValidatorDomain } from '../modules/sync_v2/domain/mutation-validator';

async function setup() {
  console.log('🔄 Setting up database for Sync V2 Verification Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

async function runVerificationSuite() {
  await setup();

  console.log('\n======================================================');
  console.log('🧪 ENTERPRISE SYNC ENGINE V2 — PHASE 3 VERIFICATION');
  console.log('======================================================\n');

  const tenant_id = 'company_test_v2';
  const device_id = 'device_mobile_001';

  // Seed company
  const client = await pgPool.connect();
  try {
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, current_revision, domain_revisions)
       VALUES ($1, 'Test Company V2', '1234567890', 'Ankara Tax Office', 0, '{"sales": 0, "stock": 0, "customer": 0, "invoice": 0, "settings": 0}'::jsonb)`,
      [tenant_id]
    );
  } finally {
    client.release();
  }

  // --------------------------------------------------------------------------
  // TEST 1: Mutation Validator Domain Unit Test
  // --------------------------------------------------------------------------
  console.log('🔹 Test 1: Mutation Validator Domain Unit Test...');
  const invalidResult = MutationValidatorDomain.validate({ client_mutation_id: '' });
  if (invalidResult.valid) {
    throw new Error('❌ Test 1 FAILED: Validator accepted invalid mutation');
  }
  const validResult = MutationValidatorDomain.validate({
    client_mutation_id: 'mut_001',
    tenant_id,
    device_id,
    domain: 'sales',
    entity_type: 'sales_order',
    entity_id: 'ord_1',
    op_type: 'INSERT',
    payload: { total: 100 },
    base_revision: 0,
  });
  if (!validResult.valid) {
    throw new Error(`❌ Test 1 FAILED: Valid mutation rejected: ${validResult.error}`);
  }
  console.log('  ✔️ Test 1 PASSED: Mutation Validator operates correctly.');

  // --------------------------------------------------------------------------
  // TEST 2: Idempotency Replay Test (100 Repetitions)
  // --------------------------------------------------------------------------
  console.log('\n🔹 Test 2: Idempotency Replay Test (100 Repetitions)...');
  const replayMutationId = 'mut_replay_100_times';
  const replayPayload: MutationPayload = {
    client_mutation_id: replayMutationId,
    device_id,
    tenant_id,
    domain: 'sales',
    entity_type: 'sales_order',
    entity_id: 'ord_replay_100',
    op_type: 'INSERT',
    payload: { total: 250.0 },
    client_timestamp: Date.now(),
    base_revision: 0,
  };

  let appliedCount = 0;
  let skippedCount = 0;

  for (let i = 0; i < 100; i++) {
    const pushRes = await RevisionService.processMutationsBatch(tenant_id, device_id, [replayPayload]);
    const resItem = pushRes.results[0];
    if (resItem.status === 'APPLIED') appliedCount++;
    if (resItem.status === 'IDEMPOTENT_SKIPPED') skippedCount++;
  }

  if (appliedCount !== 1 || skippedCount !== 99) {
    throw new Error(`❌ Test 2 FAILED: Expected 1 APPLIED and 99 IDEMPOTENT_SKIPPED, got applied: ${appliedCount}, skipped: ${skippedCount}`);
  }
  console.log(`  ✔️ Test 2 PASSED: 100 replay pushes produced exactly 1 APPLIED revision and 99 IDEMPOTENT_SKIPPED.`);

  // --------------------------------------------------------------------------
  // TEST 3: Delta Vector Consistency Test
  // --------------------------------------------------------------------------
  console.log('\n🔹 Test 3: Delta Vector Consistency Test...');
  // Push 5 sales mutations and 3 stock mutations
  const salesMutations: MutationPayload[] = [1, 2, 3, 4, 5].map((idx) => ({
    client_mutation_id: `mut_sales_${idx}`,
    device_id,
    tenant_id,
    domain: 'sales',
    entity_type: 'sales_order',
    entity_id: `ord_s_${idx}`,
    op_type: 'INSERT',
    payload: { amount: idx * 10 },
    client_timestamp: Date.now(),
    base_revision: 1,
  }));

  const stockMutations: MutationPayload[] = [1, 2, 3].map((idx) => ({
    client_mutation_id: `mut_stock_${idx}`,
    device_id,
    tenant_id,
    domain: 'stock',
    entity_type: 'stock_item',
    entity_id: `stk_${idx}`,
    op_type: 'UPDATE',
    payload: { qty: idx * 5 },
    client_timestamp: Date.now(),
    base_revision: 0,
  }));

  await RevisionService.processMutationsBatch(tenant_id, device_id, salesMutations);
  await RevisionService.processMutationsBatch(tenant_id, device_id, stockMutations);

  // Client requests delta with client_vectors: { sales: 1, stock: 0 }
  // Should receive sales revisions 2..6 (5 items) and stock revisions 1..3 (3 items) -> Total 8 items
  const deltaRes = await DeltaBuilderService.fetchDeltas(tenant_id, { sales: 1, stock: 0 });

  if (deltaRes.deltas.length !== 8) {
    throw new Error(`❌ Test 3 FAILED: Expected 8 delta items, got ${deltaRes.deltas.length}`);
  }

  // Client requests delta with fully aligned vector { sales: 6, stock: 3 } -> Should return 0 items
  const alignedDeltaRes = await DeltaBuilderService.fetchDeltas(tenant_id, { sales: 6, stock: 3 });
  if (alignedDeltaRes.deltas.length !== 0) {
    throw new Error(`❌ Test 3 FAILED: Expected 0 delta items for aligned vector, got ${alignedDeltaRes.deltas.length}`);
  }
  console.log('  ✔️ Test 3 PASSED: Vector delta pull accurately filtered domain revisions.');

  // --------------------------------------------------------------------------
  // TEST 4: Conflict Golden Test (Field-Level Merge)
  // --------------------------------------------------------------------------
  console.log('\n🔹 Test 4: Conflict Golden Test (Field-Level Merge)...');
  const existingPayload = { price: 100.0, title: 'Original Item', status: 'ACTIVE', is_deleted: false };
  const incomingConflictMutation: MutationPayload = {
    client_mutation_id: 'mut_conflict_1',
    device_id: 'device_mobile_002',
    tenant_id,
    domain: 'stock',
    entity_type: 'stock_item',
    entity_id: 'stk_1',
    op_type: 'UPDATE',
    payload: { price: 120.0, notes: 'Discount applied' },
    client_timestamp: Date.now(),
    base_revision: 1,
  };

  const mergeResult = ConflictResolverDomain.reconcile(incomingConflictMutation, existingPayload, 5);
  if (!mergeResult.hasConflict || mergeResult.strategyUsed !== 'FIELD_LEVEL_MERGE') {
    throw new Error(`❌ Test 4 FAILED: Expected FIELD_LEVEL_MERGE, got ${mergeResult.strategyUsed}`);
  }

  if (mergeResult.resolvedPayload.price !== 120.0 || mergeResult.resolvedPayload.title !== 'Original Item' || mergeResult.resolvedPayload.notes !== 'Discount applied') {
    throw new Error(`❌ Test 4 FAILED: Field merge payload incorrect: ${JSON.stringify(mergeResult.resolvedPayload)}`);
  }
  console.log('  ✔️ Test 4 PASSED: Conflict Golden Test merged fields deterministically.');

  // --------------------------------------------------------------------------
  // TEST 5: Snapshot Builder & Hydration Test
  // --------------------------------------------------------------------------
  console.log('\n🔹 Test 5: Snapshot Compaction Test...');
  const snapshot = await SnapshotBuilderService.createSnapshot(tenant_id, 'sales');
  if (!snapshot || snapshot.entities.length === 0) {
    throw new Error('❌ Test 5 FAILED: Snapshot creation returned empty entities');
  }
  const fetchedSnapshot = await SnapshotBuilderService.getLatestSnapshot(tenant_id, 'sales');
  if (!fetchedSnapshot || fetchedSnapshot.snapshot_revision !== snapshot.snapshot_revision) {
    throw new Error('❌ Test 5 FAILED: Fetched snapshot revision mismatch');
  }
  console.log('  ✔️ Test 5 PASSED: Snapshot creation and retrieval verified.');

  // --------------------------------------------------------------------------
  // TEST 6: Tombstone 30-Day Retention Purge Test
  // --------------------------------------------------------------------------
  console.log('\n🔹 Test 6: Tombstone Purge Test...');
  // Push a DELETE mutation
  const deleteMutation: MutationPayload = {
    client_mutation_id: 'mut_del_1',
    device_id,
    tenant_id,
    domain: 'sales',
    entity_type: 'sales_order',
    entity_id: 'ord_s_1',
    op_type: 'DELETE',
    payload: { is_deleted: true },
    client_timestamp: Date.now(),
    base_revision: 6,
  };
  await RevisionService.processMutationsBatch(tenant_id, device_id, [deleteMutation]);

  // Backdate tombstone deleted_at to 31 days ago
  const dbClient = await pgPool.connect();
  try {
    await dbClient.query(`UPDATE sync_tombstones SET deleted_at = CURRENT_TIMESTAMP - INTERVAL '31 days' WHERE entity_id = 'ord_s_1'`);
  } finally {
    dbClient.release();
  }

  const purgedCount = await TombstoneManagerService.purgeExpiredTombstones(30);
  if (purgedCount !== 1) {
    throw new Error(`❌ Test 6 FAILED: Expected 1 purged tombstone, got ${purgedCount}`);
  }
  console.log('  ✔️ Test 6 PASSED: 31-day expired tombstone purged successfully.');

  console.log('\n======================================================');
  console.log('🎉 ALL PHASE 3 VERIFICATION TESTS PASSED SUCCESSFULLY!');
  console.log('======================================================\n');
}

if (require.main === module) {
  runVerificationSuite()
    .then(() => {
      process.exit(0);
    })
    .catch((err) => {
      console.error('❌ Phase 3 Verification Suite Failed:', err);
      process.exit(1);
    });
}

// server/src/test/ac_monitoring.test.ts
// Serenut OS — Monitoring / Telemetry Acceptance Criteria Test
// Verification: AC 7.1, 7.2

import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { ConnectionRegistry } from '../modules/realtime/connection-registry';
import { RealtimeBroadcastService } from '../modules/realtime/broadcast.service';

async function setup() {
  console.log('🔄 Setting up database for Monitoring Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

async function run() {
  await setup();

  try {
    console.log('📊 Verifying Telemetry counters and ConnectionRegistry metrics...');
    
    // Simulate connection register
    const dummyWs = {} as any;
    const meta = {
      userId: 'user-mock',
      userName: 'User Mock',
      companyId: 'comp-mock',
      ipAddress: '127.0.0.1',
      userAgent: 'MockAgent',
      connectedAt: new Date(),
      reconnectCount: 0
    };
    ConnectionRegistry.register(dummyWs, meta);
    const wsCount = ConnectionRegistry.getActiveConnectionsCount();
    if (wsCount !== 1) {
      throw new Error(`Expected active WebSocket connection count to be 1, got: ${wsCount}`);
    }
    console.log('  ✔️ WebSocket registry successfully tracked active connections.');

    // Simulate event counts
    await RealtimeBroadcastService.publishEvent('comp-mock', 'TestEvent', {});
    const sentCount = RealtimeBroadcastService.getSentEventsCount();
    if (sentCount !== 1) {
      throw new Error(`Expected sent events count to be 1, got: ${sentCount}`);
    }
    console.log('  ✔️ Telemetry logged realtime event count successfully.');

    // Clean connections registry
    ConnectionRegistry.unregister(dummyWs);
    const wsCountAfter = ConnectionRegistry.getActiveConnectionsCount();
    if (wsCountAfter !== 0) {
      throw new Error(`Expected active WebSocket connections count to be 0, got: ${wsCountAfter}`);
    }
    console.log('  ✔️ WebSocket registry successfully untracked connection.');

    console.log('🏆 AC Monitoring Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Monitoring Tests: FAIL', err);
    process.exit(1);
  }
}

run();

// server/src/test/ac_support.test.ts
// Serenut OS — Support Ticket SLA Acceptance Criteria Test
// Verification: AC 6.1, 6.2

import { pgPool } from '../config/database';
import { SupportService } from '../modules/support/support.service';
import { runMigrations } from '../migrations';

async function setup() {
  console.log('🔄 Setting up database for Support SLA Test...');
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

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    console.log('🌱 Seeding company and user...');
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('support-comp', 'Support Corp', '1122334455', 'Kadikoy', 'active')`
    );
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active)
       VALUES ('support-user', 'support-comp', 'Support Owner', 'owner@support.com', 'hash', true)`
    );
    await client.query('COMMIT');

    // 1. Create High Priority Ticket — SLA should be 2 hours (P1)
    console.log('🎫 Creating high priority support ticket (2h SLA expected)...');
    const ticketHigh = await SupportService.createTicket({
      companyId: 'support-comp',
      subject: 'High Priority Issue',
      body: 'High priority description',
      priority: 'P1'
    });

    const diffHigh = ticketHigh.sla_deadline_at.getTime() - ticketHigh.created_at.getTime();
    const hoursHigh = diffHigh / (1000 * 60 * 60);
    if (Math.round(hoursHigh) !== 2) {
      throw new Error(`Expected SLA deadline to be 2 hours, got: ${hoursHigh} hours`);
    }
    console.log('  ✔️ High priority SLA deadline correctly set to 2 hours.');

    // 2. Create Medium Priority Ticket — SLA should be 6 hours (P2)
    console.log('🎫 Creating medium priority support ticket (6h SLA expected)...');
    const ticketMed = await SupportService.createTicket({
      companyId: 'support-comp',
      subject: 'Medium Priority Issue',
      body: 'Medium description',
      priority: 'P2'
    });

    const diffMed = ticketMed.sla_deadline_at.getTime() - ticketMed.created_at.getTime();
    const hoursMed = diffMed / (1000 * 60 * 60);
    if (Math.round(hoursMed) !== 6) {
      throw new Error(`Expected SLA deadline to be 6 hours, got: ${hoursMed} hours`);
    }
    console.log('  ✔️ Medium priority SLA deadline correctly set to 6 hours.');

    // 3. Create Low Priority Ticket — SLA should be 24 hours (P3)
    console.log('🎫 Creating low priority support ticket (24h SLA expected)...');
    const ticketLow = await SupportService.createTicket({
      companyId: 'support-comp',
      subject: 'Low Priority Issue',
      body: 'Low description',
      priority: 'P3'
    });

    const diffLow = ticketLow.sla_deadline_at.getTime() - ticketLow.created_at.getTime();
    const hoursLow = diffLow / (1000 * 60 * 60);
    if (Math.round(hoursLow) !== 24) {
      throw new Error(`Expected SLA deadline to be 24 hours, got: ${hoursLow} hours`);
    }
    console.log('  ✔️ Low priority SLA deadline correctly set to 24 hours.');

    console.log('🏆 AC Support Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Support Tests: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();

import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { enqueueNotification, reserveNotificationCredit } from '../workers/notification.worker';

async function run() {
  await runMigrations(pgPool);
  await pgPool.query("SET app.bypass_rls='true'");
  await pgPool.query(`INSERT INTO companies(id,name,tax_number,status) VALUES('credit-company','Credit Co','credit-tax','active')
    ON CONFLICT(id) DO NOTHING`);
  await pgPool.query(`INSERT INTO company_notification_credits(company_id,sms_credits,email_credits,whatsapp_credits)
    VALUES('credit-company',3,0,0) ON CONFLICT(company_id) DO UPDATE SET sms_credits=3`);
  await enqueueNotification({
    notification_id: 'durable-producer-test', company_id: 'credit-company',
    channel: 'push', recipient: 'device-token', title: 'Test', body: 'Durable',
  });
  const durable = await pgPool.query(
    `SELECT status FROM notification_queue WHERE id='durable-producer-test'`,
  );
  if (durable.rows[0]?.status !== 'pending') {
    throw new Error('Notification producer bypassed the durable outbox.');
  }
  const values: string[] = [];
  const params: any[] = [];
  for (let i=0;i<10;i++) {
    values.push(`($${params.length+1},'credit-company','sms','5550000000','test','pending',NOW())`);
    params.push(`credit-notification-${i}`);
  }
  await pgPool.query(`INSERT INTO notification_queue(id,company_id,channel,recipient,body,status,scheduled_at)
    VALUES ${values.join(',')} ON CONFLICT(id) DO UPDATE SET status='pending'`, params);
  const allowed = await Promise.all(Array.from({length:10},(_,i) =>
    reserveNotificationCredit(`credit-notification-${i}`,'credit-company','sms')));
  if (allowed.filter(Boolean).length !== 3) throw new Error('Credit limit was overspent under concurrency.');
  const before = await pgPool.query(`SELECT sms_credits FROM company_notification_credits WHERE company_id='credit-company'`);
  if (Number(before.rows[0].sms_credits) !== 0) throw new Error('Reserved credit balance is incorrect.');
  const same = await Promise.all(Array.from({length:5},() =>
    reserveNotificationCredit('credit-notification-0','credit-company','sms')));
  if (!same.every(Boolean)) throw new Error('Existing reservation was not idempotent.');
  const after = await pgPool.query(`SELECT sms_credits FROM company_notification_credits WHERE company_id='credit-company'`);
  if (Number(after.rows[0].sms_credits) !== 0) throw new Error('Idempotent reservation deducted more than once.');
  console.log('✔ Notification credits are atomically reserved and cannot be overspent.');
}

run().then(()=>process.exit(0)).catch(error=>{ console.error('❌ Notification reservation test failed',error); process.exit(1); });

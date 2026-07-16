import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';

async function run() {
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    await runMigrations(pgPool);
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const plans = await client.query(
      `SELECT id, price::numeric, device_limit, store_limit, user_limit
       FROM plans WHERE id IN ('plan-basic','plan-pro') ORDER BY id`
    );
    const basic = plans.rows.find((p: any) => p.id === 'plan-basic');
    const pro = plans.rows.find((p: any) => p.id === 'plan-pro');
    if (Number(basic.price) !== 149 || basic.device_limit !== 2 || basic.store_limit !== 1 || basic.user_limit !== 4) {
      throw new Error('Starter commercial limits are incorrect');
    }
    if (Number(pro.price) !== 399 || pro.device_limit !== 6 || pro.store_limit !== 3 || pro.user_limit !== 11) {
      throw new Error('Pro commercial limits are incorrect');
    }

    await client.query(`
      INSERT INTO companies (id, name, tax_number, status) VALUES
        ('foundation-a','Firma A','11111111111','trial'),
        ('foundation-b','Firma B','22222222222','trial')
    `);
    await client.query(`
      INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES
        ('foundation-user-a','foundation-a','Sahip A','a@example.test','hash',false),
        ('foundation-user-b','foundation-b','Sahip B','b@example.test','hash',true)
    `);
    await client.query(`
      INSERT INTO email_verification_tokens (id,user_id,token_hash,expires_at)
      VALUES ('evt-foundation','foundation-user-a',REPEAT('a',64),NOW()+INTERVAL '30 minutes')
    `);
    const verification = await client.query(
      `UPDATE users SET email_verified_at=NOW(), is_active=true WHERE id='foundation-user-a'
       RETURNING is_active,email_verified_at`
    );
    if (!verification.rows[0].is_active || !verification.rows[0].email_verified_at) {
      throw new Error('Email verification activation failed');
    }

    await client.query(`
      INSERT INTO roles (id,company_id,name) VALUES
        ('role-a','foundation-a','Kasiyer Özel'),
        ('role-b','foundation-b','Kasiyer Özel')
    `);
    let duplicateRejected = false;
    await client.query('SAVEPOINT duplicate_role_check');
    try {
      await client.query("INSERT INTO roles (id,company_id,name) VALUES ('role-a2','foundation-a','Kasiyer Özel')");
    } catch (err: any) {
      duplicateRejected = err.code === '23505';
      await client.query('ROLLBACK TO SAVEPOINT duplicate_role_check');
    }
    if (!duplicateRejected) throw new Error('Duplicate tenant role was not rejected');

    await client.query(`
      INSERT INTO subscriptions (id,company_id,plan_id,status,current_period_start,current_period_end)
      VALUES ('sub-foundation','foundation-a','plan-basic','trialing',NOW(),NOW()+INTERVAL '30 days');
      INSERT INTO license_entitlements (id,company_id,subscription_id,plan_id,status,device_limit,store_limit,valid_from,valid_until)
      VALUES ('ent-foundation','foundation-a','sub-foundation','plan-basic','trial',2,1,NOW(),NOW()+INTERVAL '30 days');
      INSERT INTO device_activations (id,entitlement_id,company_id,device_hash,device_name,platform,status)
      VALUES ('android-foundation','ent-foundation','foundation-a','hash-android','Android Ana','android','active');
      INSERT INTO company_sms_gateways (company_id,device_activation_id,selected_by)
      VALUES ('foundation-a','android-foundation','foundation-user-a');
      INSERT INTO notification_queue (id,company_id,channel,recipient,body,status,scheduled_at,client_message_id)
      VALUES ('sms-foundation','foundation-a','sms','905551112233','Test SMS','queued',NOW(),'client-foundation');
    `);
    const claimed = await client.query(`
      UPDATE notification_queue SET status='delivered_to_device',gateway_device_id='android-foundation',gateway_claimed_at=NOW()
      WHERE id='sms-foundation' AND status='queued' RETURNING id,status,gateway_device_id
    `);
    if (claimed.rows[0]?.status !== 'delivered_to_device' || claimed.rows[0]?.gateway_device_id !== 'android-foundation') {
      throw new Error('SMS gateway claim failed');
    }
    const sent = await client.query(`
      UPDATE notification_queue SET status='sent',delivered_at=NOW()
      WHERE id='sms-foundation' AND gateway_device_id='android-foundation' RETURNING status,delivered_at
    `);
    if (sent.rows[0]?.status !== 'sent' || !sent.rows[0]?.delivered_at) throw new Error('SMS result failed');

    await client.query('COMMIT');
    console.log('✅ SaaS foundation acceptance: PASS');
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ SaaS foundation acceptance: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();

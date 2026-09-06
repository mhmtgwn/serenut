const { pgPool } = require('./dist/config/database');
const { emailVerificationEmail } = require('./dist/modules/mail/mail.service');
const crypto = require('crypto');

async function main() {
  const client = await pgPool.connect();
  try {
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const userRes = await client.query(
      "SELECT id, name, email, company_id FROM users WHERE LOWER(email) = 'mhmtgwn@gmail.com' LIMIT 1"
    );
    if (userRes.rows.length === 0) {
      console.log('User not found');
      return;
    }
    const user = userRes.rows[0];
    const verificationToken = crypto.randomBytes(32).toString('hex');
    const verificationHash = crypto.createHash('sha256').update(verificationToken).digest('hex');

    await client.query(
      `INSERT INTO email_verification_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '24 hours')`,
      [`evt-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`, user.id, verificationHash]
    );

    const publicUrl = (process.env.PUBLIC_URL || 'https://serenut.com').replace(/\/$/, '');
    const message = emailVerificationEmail({
      userName: user.name,
      verificationLink: `${publicUrl}/api/v1/auth/verify-email?token=${verificationToken}`
    });
    const notificationId = `notif-${Date.now()}-verify`;
    await client.query(
      `INSERT INTO notification_queue (id, company_id, channel, recipient, title, body, status, scheduled_at)
       VALUES ($1, $2, 'email', $3, $4, $5, 'pending', NOW())`,
      [notificationId, user.company_id, user.email, message.subject, message.html]
    );
    console.log('✅ FRESH verification email & token generated and queued for:', user.email);
  } catch (err) {
    console.error('Error queueing verification email:', err);
  } finally {
    client.release();
    process.exit(0);
  }
}

main();

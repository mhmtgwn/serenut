import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';

async function main() {
  const email = process.argv[2] || process.env.SYSADMIN_DEFAULT_EMAIL;
  const password = process.argv[3] || process.env.SYSADMIN_DEFAULT_PASSWORD;

  if (!email || !password) {
    console.error('ERROR: Lütfen e-posta ve şifre argümanlarını veya ENV tanımlarını sağlayın.');
    console.log('Kullanım: ts-node get-sysadmin.ts <email> <password>');
    process.exit(1);
  }

  try {
    const hash = await AuthService.hashPassword(password);
    
    const res = await pgPool.query(`
      UPDATE users 
      SET password_hash = $1, failed_login_attempts = 0, locked_until = NULL, is_active = true
      WHERE email = $2
      RETURNING id, name, email
    `, [hash, email]);
    
    if (res.rows.length > 0) {
      console.log('PASSWORD_RESET_SUCCESS:', JSON.stringify(res.rows[0], null, 2));
    } else {
      console.log('USER_NOT_FOUND');
    }
  } catch (err: any) {
    console.error('ERROR:', err.message);
  } finally {
    await pgPool.end();
  }
}

main();

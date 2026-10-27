import crypto from 'crypto';
import bcrypt from 'bcrypt';
import { pgPool } from '../config/database';
import { PasswordRecoveryService } from '../modules/auth/password-recovery.service';

const BCRYPT_ROUNDS = 12;
const PLATFORM_COMPANY_ID = 'serenut_cloud';
const PLATFORM_COMPANY_NAME = 'Serenut Platform';
const PLATFORM_TAX_NUMBER = '0000000000';

function readHidden(prompt: string): Promise<string> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error(
      'Etkileşimli terminal (TTY) bulunamadı. Otomatik güçlü parola üretmek için komuta --generate-password ekleyin.'
    );
  }

  return new Promise((resolve, reject) => {
    let value = '';
    process.stdout.write(prompt);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding('utf8');

    const cleanup = () => {
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdin.removeListener('data', onData);
      process.stdout.write('\n');
    };

    const onData = (key: string) => {
      if (key === '\u0003') {
        cleanup();
        reject(new Error('İşlem iptal edildi.'));
      } else if (key === '\r' || key === '\n') {
        cleanup();
        resolve(value);
      } else if (key === '\u007f' || key === '\b') {
        value = value.slice(0, -1);
      } else if (key >= ' ') {
        value += key;
      }
    };

    process.stdin.on('data', onData);
  });
}

function validatePassword(password: string): void {
  if (password.length < 10 || !/\p{L}/u.test(password) || !/\d/.test(password)) {
    throw new Error('Parola en az 10 karakter olmalı ve harf ile rakam içermelidir.');
  }
}

function generateStrongPassword(): string {
  const token = crypto.randomBytes(6).toString('hex');
  return `SrnAdmin-${token.slice(0, 4)}-${token.slice(4, 8)}-${token.slice(8, 12)}9`;
}

async function main() {
  const rawArgs = process.argv.slice(2);
  const isReset = rawArgs.includes('--reset');
  const shouldGeneratePw = rawArgs.includes('--generate-password') || rawArgs.includes('--auto');
  const positional = rawArgs.filter((a) => !a.startsWith('--'));

  let name = isReset
    ? (positional.length > 1 ? positional[0]?.trim() : 'Sysadmin')
    : positional[0]?.trim();
  let email = (isReset
    ? (positional.length > 1 ? positional[1] : positional[0])
    : positional[1]
  )?.trim().toLowerCase();

  const client = await pgPool.connect();

  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query("SELECT pg_advisory_xact_lock(hashtext('serenut:create-sysadmin'))");

    if (isReset && !email) {
      const sysadmins = await client.query(
        `SELECT u.id, u.name, u.email
         FROM users u
         JOIN user_roles ur ON ur.user_id = u.id
         JOIN roles r ON r.id = ur.role_id
         WHERE r.name = 'sysadmin' AND u.deleted_at IS NULL
         ORDER BY u.is_active DESC, u.created_at ASC`
      );
      if (sysadmins.rows.length === 0) {
        throw new Error(
          'Sistemde kayıtlı bir sysadmin bulunamadı. Yeni oluşturmak için:\n' +
          '  npm run create:sysadmin -- "Admin" "sysadmin@serenut.com"'
        );
      }
      if (sysadmins.rows.length > 1) {
        const list = sysadmins.rows.map((r: any) => `  - ${r.email} (${r.name})`).join('\n');
        throw new Error(
          `Birden fazla sysadmin hesabı bulundu. Lütfen sıfırlanacak e-postayı belirtin:\n${list}\n` +
          `Örnek: npm run reset:sysadmin -- "${sysadmins.rows[0].email}"`
        );
      }
      email = String(sysadmins.rows[0].email).trim().toLowerCase();
      name = sysadmins.rows[0].name || 'Sysadmin';
      console.log(`Tespit edilen sysadmin hesabı: ${name} <${email}>`);
    }

    if (!name || !email || !/^\S+@\S+\.\S+$/.test(email)) {
      throw new Error(
        'Kullanım:\n' +
        '  Mevcut sysadmin şifresini sıfırlamak: npm run reset:sysadmin -- "sysadmin@serenut.com"\n' +
        '  Otomatik şifre üreterek sıfırlamak:   npm run reset:sysadmin -- --generate-password\n' +
        '  Yeni sysadmin oluşturmak:             npm run create:sysadmin -- "Admin" "sysadmin@serenut.com"'
      );
    }

    let password: string;
    if (shouldGeneratePw) {
      password = generateStrongPassword();
    } else {
      password = await readHidden('Yeni Parola: ');
      const confirmation = await readHidden('Parola Tekrar: ');
      if (password !== confirmation) throw new Error('Parolalar eşleşmiyor.');
    }
    validatePassword(password);

    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    const existingUserRes = await client.query(
      'SELECT id, name FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL LIMIT 1',
      [email]
    );

    if (existingUserRes.rows.length > 0 && !isReset) {
      throw new Error(
        `Bu e-posta adresiyle kayıtlı bir kullanıcı zaten mevcut. Parolasını sıfırlamak için:\n  npm run reset:sysadmin -- "${email}"`
      );
    }

    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ($1, $2, $3, 'Platform', 'active')
       ON CONFLICT (id) DO NOTHING`,
      [PLATFORM_COMPANY_ID, PLATFORM_COMPANY_NAME, PLATFORM_TAX_NUMBER]
    );

    await client.query(
      `INSERT INTO roles (id, name, description)
       VALUES ('sysadmin', 'sysadmin', 'Serenut platform system administrator')
       ON CONFLICT DO NOTHING`
    );
    const roleResult = await client.query(`SELECT id FROM roles WHERE name='sysadmin' LIMIT 1`);
    if (!roleResult.rowCount) throw new Error('Sysadmin rolü oluşturulamadı.');

    let userId: string;
    let displayName: string;

    if (existingUserRes.rows.length > 0) {
      userId = existingUserRes.rows[0].id;
      displayName = existingUserRes.rows[0].name || name;

      await client.query(
        `UPDATE users
         SET password_hash = $1,
             is_active = true,
             failed_login_attempts = 0,
             locked_until = NULL,
             email_verified_at = COALESCE(email_verified_at, NOW()),
             token_version = COALESCE(token_version, 0) + 1,
             updated_at = NOW()
         WHERE id = $2`,
        [passwordHash, userId]
      );

      await client.query(
        `INSERT INTO user_roles (user_id, role_id)
         VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [userId, roleResult.rows[0].id]
      );

      await client.query(
        `UPDATE sessions
         SET is_revoked = true, updated_at = NOW()
         WHERE user_id = $1`,
        [userId]
      );
    } else {
      userId = `sysadmin-${crypto.randomUUID()}`;
      displayName = name;

      await client.query(
        `INSERT INTO users
           (id, company_id, name, email, password_hash, is_active, email_verified_at)
         VALUES ($1, $2, $3, $4, $5, true, NOW())`,
        [userId, PLATFORM_COMPANY_ID, name, email, passwordHash]
      );
      await client.query(
        'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)',
        [userId, roleResult.rows[0].id]
      );
    }

    const recoveryCodes = await PasswordRecoveryService.issueRecoveryCodes(client, userId);

    await client.query('COMMIT');
    console.log(
      existingUserRes.rows.length > 0
        ? `\n✅ Sysadmin parolası sıfırlandı ve eski oturumlar sonlandırıldı: ${displayName} <${email}>`
        : `\n✅ Sysadmin oluşturuldu: ${displayName} <${email}>`
    );
    if (shouldGeneratePw) {
      console.log(`\n🔑 Yeni Geçici / Güçlü Parolanız (yalnızca şimdi gösterilir):\n${password}`);
    }
    console.log('\n🛡️ Yeni Kurtarma Kodlarınız (yalnızca şimdi gösterilir):');
    recoveryCodes.forEach((code) => console.log(code));
    console.log('\nKodları çevrimdışı ve güvenli bir yerde saklayın.');
    console.log('Şifrenizi unutursanız /forgot-password ekranından sadece E-posta + Kurtarma Kodu ile giriş yapabilirsiniz.');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pgPool.end();
  }
}

main().catch(async (error: Error) => {
  console.error(`HATA: ${error.message}`);
  await pgPool.end().catch(() => undefined);
  process.exitCode = 1;
});

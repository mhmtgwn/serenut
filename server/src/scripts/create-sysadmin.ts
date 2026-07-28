import crypto from 'crypto';
import bcrypt from 'bcrypt';
import { pgPool } from '../config/database';

const BCRYPT_ROUNDS = 12;
const PLATFORM_COMPANY_ID = 'serenut_cloud';
const PLATFORM_COMPANY_NAME = 'Serenut Platform';
const PLATFORM_TAX_NUMBER = '0000000000';

function readHidden(prompt: string): Promise<string> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error('Parola yalnız etkileşimli bir terminalden girilebilir.');
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
  if (password.length < 8) {
    throw new Error('Parola en az 8 karakter olmalıdır.');
  }
}

async function main() {
  const name = process.argv[2]?.trim();
  const email = process.argv[3]?.trim().toLowerCase();

  if (!name || !email || !/^\S+@\S+\.\S+$/.test(email)) {
    throw new Error(
      'Kullanım: npm run create:sysadmin -- "Admin" "sysadmin@serenut.com"'
    );
  }

  const password = await readHidden('Parola: ');
  const confirmation = await readHidden('Parola tekrar: ');
  if (password !== confirmation) throw new Error('Parolalar eşleşmiyor.');
  validatePassword(password);

  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const client = await pgPool.connect();

  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query("SELECT pg_advisory_xact_lock(hashtext('serenut:create-sysadmin'))");

    const existing = await client.query(
      `SELECT u.email
         FROM users u
         JOIN user_roles ur ON ur.user_id = u.id
         JOIN roles r ON r.id = ur.role_id
        WHERE r.name = 'sysadmin'
        LIMIT 1`
    );
    if (existing.rows.length > 0) {
      throw new Error(`Sysadmin hesabı zaten mevcut: ${existing.rows[0].email}`);
    }

    const duplicateEmail = await client.query(
      'SELECT 1 FROM users WHERE LOWER(email) = $1 LIMIT 1',
      [email]
    );
    if (duplicateEmail.rows.length > 0) {
      throw new Error('Bu e-posta adresiyle kayıtlı bir kullanıcı zaten mevcut.');
    }

    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ($1, $2, $3, 'Platform', 'active')
       ON CONFLICT (id) DO NOTHING`,
      [PLATFORM_COMPANY_ID, PLATFORM_COMPANY_NAME, PLATFORM_TAX_NUMBER]
    );

    const roleResult = await client.query(
      `INSERT INTO roles (id, name, description)
       VALUES ('sysadmin', 'sysadmin', 'Serenut platform system administrator')
       ON CONFLICT (name) DO UPDATE SET description = EXCLUDED.description
       RETURNING id`
    );

    const userId = `sysadmin-${crypto.randomUUID()}`;
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

    await client.query('COMMIT');
    console.log(`Sysadmin oluşturuldu: ${name} <${email}>`);
    console.log('Parola daha sonra Hesap Ayarları ekranından değiştirilebilir.');
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

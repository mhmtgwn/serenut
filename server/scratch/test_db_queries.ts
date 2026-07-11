import { pgPool } from '../src/config/database';

async function main() {
  try {
    console.log('Testing GET /licenses query...');
    const result = await pgPool.query(`
      SELECT l.*, c.name as company_name 
      FROM licenses l 
      JOIN companies c ON l.company_id = c.id 
      ORDER BY l.created_at DESC
    `);
    console.log(`Success! Found ${result.rows.length} licenses:`);
    console.log(JSON.stringify(result.rows, null, 2));

    const companies = await pgPool.query('SELECT * FROM companies');
    console.log(`Found ${companies.rows.length} companies:`);
    console.log(JSON.stringify(companies.rows, null, 2));

    const users = await pgPool.query('SELECT id, company_id, name, email, is_active FROM users');
    console.log(`Found ${users.rows.length} users:`);
    console.log(JSON.stringify(users.rows, null, 2));

    const userRoles = await pgPool.query(`
      SELECT ur.*, r.name as role_name 
      FROM user_roles ur 
      JOIN roles r ON ur.role_id = r.id
    `);
    console.log(`Found ${userRoles.rows.length} user roles:`);
    console.log(JSON.stringify(userRoles.rows, null, 2));

  } catch (err) {
    console.error('Database query failed:', err);
  } finally {
    await pgPool.end();
  }
}

main();

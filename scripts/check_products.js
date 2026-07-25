const { pgPool } = require('/app/dist/config/database');
pgPool.query('SELECT id, name, company_id, updated_at FROM products ORDER BY updated_at DESC LIMIT 5')
  .then(r => { console.log(JSON.stringify(r.rows, null, 2)); process.exit(0); })
  .catch(e => { console.error(e.message); process.exit(1); });

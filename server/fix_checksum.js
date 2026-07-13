const { Client } = require('pg');
const c = new Client('postgres://postgres:postgres@127.0.0.1:5432/nutopiano');
c.connect().then(() => {
  return c.query("UPDATE schema_migrations SET checksum = 'feb127693e2590df19ae23ab017b0bea3f52184a0abb659426343759cc092c7e' WHERE version = 1");
}).then(() => {
  console.log('Done');
  c.end();
}).catch(console.error);

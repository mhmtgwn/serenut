const { Client } = require('pg');
async function run() {
  const client = new Client('postgres://postgres:postgres@127.0.0.1:5432/postgres');
  try {
    await client.connect();
    await client.query('CREATE DATABASE serenut_test');
    console.log("Database created");
  } catch (err) {
    console.error("Failed:", err.message);
  } finally {
    client.end();
  }
}
run();

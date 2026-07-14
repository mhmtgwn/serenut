const { Client } = require('pg');
async function run() {
  const client = new Client('postgres://postgres:postgres@127.0.0.1:5432/postgres');
  try {
    await client.connect();
    console.log("Connected with postgres:postgres");
  } catch (err) {
    console.error("postgres:postgres failed:", err.message);
  }
}
run();

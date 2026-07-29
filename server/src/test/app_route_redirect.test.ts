import assert from 'assert';

async function run() {
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = process.env.JWT_SECRET
    || 'test_jwt_secret_must_be_at_least_32_characters_long';
  process.env.DATABASE_URL = process.env.DATABASE_URL
    || 'postgresql://test:test@127.0.0.1:5432/test';

  const request = (await import('supertest')).default;
  const { app } = await import('../server');

  const slashless = await request(app).get('/app');
  assert.equal(slashless.status, 301);
  assert.equal(slashless.headers.location, '/app/');

  const canonical = await request(app).get('/app/');
  assert.equal(canonical.status, 200);
  assert.match(canonical.text, /<!doctype html>/i);

  console.log('app route redirect regression test passed');
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});

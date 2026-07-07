/**
 * sprint6_security_verification.ts
 * 
 * Faz 6: Security Hardening — Verification Tests
 * Tests:
 *  1. Rate limiting Redis-only check (returns 503 if Redis is down)
 *  2. JWT ACCESS_TOKEN_EXPIRY verification (15 minutes limit)
 *  3. JWT jti claim presence
 *  4. Token blacklisting upon logout
 * 
 * Run: npx ts-node src/test/sprint6_security_verification.ts
 */

import { pgPool, redisClient } from '../config/database';
import { runMigrations } from '../migrations';
import { AuthService } from '../modules/auth/auth.service';
import jwt from 'jsonwebtoken';

let passed = 0;
let failed = 0;
const results: { name: string; ok: boolean; detail?: string }[] = [];

function pass(name: string, detail?: string) {
  console.log(`  ✅ [PASS] ${name}${detail ? ' — ' + detail : ''}`);
  passed++;
  results.push({ name, ok: true, detail });
}

function fail(name: string, detail?: string) {
  console.error(`  ❌ [FAIL] ${name}${detail ? ' — ' + detail : ''}`);
  failed++;
  results.push({ name, ok: false, detail });
}

async function runBypassingRLS(sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const res = await client.query(sql, params);
    await client.query('COMMIT');
    return res;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// ─────────────────────────────────────────────────────────────────
// SETUP: Migrations and clear database
// ─────────────────────────────────────────────────────────────────
async function setupDatabase() {
  console.log('\n🔄 Resetting database schema for Faz 6 Security Verification...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
  console.log('✅ Schema ready (migrations v1–v11 applied).\n');
}

// ─────────────────────────────────────────────────────────────────
// SEED
// ─────────────────────────────────────────────────────────────────
async function seedData() {
  console.log('🌱 Seeding user data for login tests...');
  const client = await pgPool.connect();
  try {
    await client.query(`
      INSERT INTO companies (id, name, tax_number, tax_office, status)
      VALUES ('comp-sec-test', 'Security Test Co', '1234567890', 'Kadıköy', 'active')
    `);

    const hash = await AuthService.hashPassword('securepass123');
    await client.query(`
      INSERT INTO users (id, company_id, name, email, password_hash, is_active)
      VALUES ('user-sec-test', 'comp-sec-test', 'Sec User', 'sec@test.com', $1, true)
    `, [hash]);

    console.log('✅ Seed data successfully populated.\n');
  } finally {
    client.release();
  }
}

// ─────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────
async function testRateLimiting() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🧪 TEST GROUP 1: Redis Rate Limiter & Fallback Prevention');
  console.log('═══════════════════════════════════════════════════════════');

  const { createRedisLimiter } = require('../middleware/rate-limit.middleware');

  // AC-6.1-1: Rate limiter returns 503 when Redis is down
  // Simulate Redis down (close connection or mock redisClient.isOpen = false)
  const originalIsOpen = redisClient ? redisClient.isOpen : false;
  if (redisClient) {
    (redisClient as any).isOpen = false;
  }

  const mockReq: any = { ip: '1.2.3.4', originalUrl: '/api/test' };
  let responseStatus = 0;
  let responseData: any = null;
  const mockRes: any = {
    status(code: number) {
      responseStatus = code;
      return this;
    },
    json(data: any) {
      responseData = data;
      return this;
    }
  };

  const limiter = createRedisLimiter({
    windowMs: 60000,
    max: 2,
    error: 'rate_limit_exceeded',
    message: 'Limit exceeded'
  });

  await limiter(mockReq, mockRes, () => {});

  if (responseStatus === 503 && responseData?.error === 'service_unavailable') {
    pass('AC-6.1-1: Rate limiter blocks with 503 when Redis is offline');
  } else {
    fail('AC-6.1-1: Rate limiter bypass/fallback occurred during Redis outage', `Status: ${responseStatus}, Data: ${JSON.stringify(responseData)}`);
  }

  // Restore Redis isOpen state
  if (redisClient) {
    (redisClient as any).isOpen = originalIsOpen;
  }
}

async function testJwtHardening() {
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('🧪 TEST GROUP 2: JWT Hardening & Blacklist');
  console.log('═══════════════════════════════════════════════════════════');

  try {
    // Perform login to generate token
    const loginRes = await AuthService.login('sec@test.com', 'securepass123', '127.0.0.1', 'Mozilla');
    const token = loginRes.access_token;

    // Decode token to verify structure
    const decoded: any = jwt.decode(token);

    // AC-6.1-2: ACCESS_TOKEN_EXPIRY = 15m
    const expDiffSeconds = decoded.exp - decoded.iat;
    if (expDiffSeconds === 15 * 60) {
      pass('AC-6.1-2: Access token expiry verified exactly as 15 minutes', `Expiry: ${expDiffSeconds}s`);
    } else {
      fail('AC-6.1-2: Access token expiry mismatch', `Expected 900s, got ${expDiffSeconds}s`);
    }

    // AC-6.1-3: jti claim is present in JWT payload
    if (decoded.jti && decoded.jti.length > 0) {
      pass('AC-6.1-3: jti unique claim verified in token payload', `jti: ${decoded.jti}`);
    } else {
      fail('AC-6.1-3: jti claim is missing');
    }

    // AC-6.1-4: Token blacklisting upon logout
    const mockRedisStore = new Map<string, string>();
    const dbModule = require('../config/database');
    const originalRedisClient = dbModule.redisClient;

    // Force mock Redis client on db module
    dbModule.redisClient = {
      isOpen: true,
      setEx: async (key: string, ttl: number, val: string) => {
        mockRedisStore.set(key, val);
        return 'OK';
      },
      get: async (key: string) => {
        return mockRedisStore.get(key) || null;
      }
    };

    // Blacklist token
    await AuthService.blacklistToken(token);
    const isBlacklistedBeforeLogoutCheck = await AuthService.isTokenBlacklisted(token);

    if (isBlacklistedBeforeLogoutCheck && mockRedisStore.has(`bl:${decoded.jti}`)) {
      pass('AC-6.1-4: Token blacklisted successfully in Redis with jti claim key');
    } else {
      fail('AC-6.1-4: Token not found in blacklist store');
    }

    // Restore original Redis client reference
    dbModule.redisClient = originalRedisClient;
  } catch (e: any) {
    fail('JWT Hardening & Blacklist test failed', e.message);
  }
}

// ─────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────
async function main() {
  console.log('╔═══════════════════════════════════════════════════════════╗');
  console.log('║   FAZ 6: SECURITY HARDENING — VERIFICATION SUITE          ║');
  console.log('║   Sprint 6.1: API Security Hardening (JWT/Limiter)        ║');
  console.log('╚═══════════════════════════════════════════════════════════╝\n');

  try {
    await setupDatabase();
    await seedData();
    await testRateLimiting();
    await testJwtHardening();
  } catch (err: any) {
    console.error('\n💥 FATAL ERROR during verification:', err.message);
    process.exit(1);
  } finally {
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log(`📊 SONUÇ: ${passed} PASS | ${failed} FAIL | Toplam: ${passed + failed}`);
    console.log('═══════════════════════════════════════════════════════════');

    if (failed === 0) {
      console.log('\n🏆 FAZ 6 SECURITY HARDENING — TÜM KABUL KRİTERLERİ KARŞILANDI!');
      console.log('🚀 API Security Hardening & JWT Blacklisting TAMAMLANDI.\n');
    } else {
      console.log('\n⚠️  Bazı kabul kriterleri karşılanmadı. Lütfen FAIL satırlarını inceleyin.\n');
    }

    try { pgPool.end(); } catch (_) {}
    process.exit(failed === 0 ? 0 : 1);
  }
}

main();

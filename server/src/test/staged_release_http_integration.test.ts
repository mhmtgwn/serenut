// server/src/test/staged_release_http_integration.test.ts
// STAGE 10.12.9 — GERÇEK EXPRESS HTTP ENTEGRASYON VE GÜVENLİK TESTİ

import assert from 'node:assert/strict';
import express, { Express } from 'express';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import { pgPool } from '../config/database';
import releaseRouter from '../modules/release/release.controller';
import updateRouter from '../modules/update/update.controller';
import adminRouter from '../modules/admin/admin.controller';

const JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-min-32-chars-long-security-antigravity';
const JWT_ISSUER = 'serenut.com';
const JWT_AUDIENCE = 'serenut-pos';

function createToken(payload: { id: string; email: string; company_id: string; roles: string[] }, expiresIn = 3600): string {
  return jwt.sign(
    {
      ...payload,
      jti: 'test-jti-' + Math.random(),
      name: 'Test User',
      roles: payload.roles || ['user'],
      permissions: ['*'],
      token_version: 1,
    },
    JWT_SECRET,
    {
      expiresIn,
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
    }
  );
}

// In-memory mock database store for HTTP integration tests
interface MockRelease {
  id: string;
  version_code: string;
  platform: string;
  channel: string;
  status: string;
  rollout_percentage: number;
  download_url: string;
  file_path: string;
  sha256_hash: string;
  release_notes: string;
  is_mandatory: boolean;
  min_required_version: string;
}

interface MockTarget {
  id: string;
  release_id: string;
  target_type: 'company' | 'device' | 'license_tier';
  target_value: string;
}

const mockReleases: MockRelease[] = [
  {
    id: 'rel-win-pilot-130',
    version_code: '1.3.0',
    platform: 'windows',
    channel: 'pilot',
    status: 'active',
    rollout_percentage: 100,
    download_url: '/api/v1/releases/download/rel-win-pilot-130',
    file_path: 'C:/fake/path/SerenutOS-v1.3.0.exe',
    sha256_hash: 'hash-pilot-130-abcdef0123456789abcdef0123456789abcdef0123456789abcdef01',
    release_notes: 'Pilot Sürümü',
    is_mandatory: false,
    min_required_version: '1.2.0',
  },
  {
    id: 'rel-win-rollout0-131',
    version_code: '1.3.1',
    platform: 'windows',
    channel: 'pilot',
    status: 'active',
    rollout_percentage: 0, // Held back
    download_url: '/api/v1/releases/download/rel-win-rollout0-131',
    file_path: 'C:/fake/path/SerenutOS-v1.3.1.exe',
    sha256_hash: 'hash-rollout0-131',
    release_notes: 'Held back rollout 0%',
    is_mandatory: false,
    min_required_version: '1.2.0',
  },
  {
    id: 'rel-win-notargets-132',
    version_code: '1.3.2',
    platform: 'windows',
    channel: 'pilot',
    status: 'active',
    rollout_percentage: 100,
    download_url: '/api/v1/releases/download/rel-win-notargets-132',
    file_path: 'C:/fake/path/SerenutOS-v1.3.2.exe',
    sha256_hash: 'hash-notargets-132',
    release_notes: 'Unconfigured pilot with 0 targets',
    is_mandatory: false,
    min_required_version: '1.2.0',
  },
  {
    id: 'rel-win-paused-133',
    version_code: '1.3.3',
    platform: 'windows',
    channel: 'pilot',
    status: 'paused', // Paused / Revoked
    rollout_percentage: 100,
    download_url: '/api/v1/releases/download/rel-win-paused-133',
    file_path: 'C:/fake/path/SerenutOS-v1.3.3.exe',
    sha256_hash: 'hash-paused-133',
    release_notes: 'Paused release',
    is_mandatory: false,
    min_required_version: '1.2.0',
  },
  {
    id: 'rel-win-stable-120',
    version_code: '1.2.0',
    platform: 'windows',
    channel: 'stable',
    status: 'active',
    rollout_percentage: 100,
    download_url: '/api/v1/updates/download/windows/latest',
    file_path: 'C:/fake/path/SerenutOS-v1.2.0.exe',
    sha256_hash: 'hash-stable-120',
    release_notes: 'General Public Stable',
    is_mandatory: false,
    min_required_version: '1.0.0',
  },
];

const mockTargets: MockTarget[] = [
  {
    id: 'tgt-1',
    release_id: 'rel-win-pilot-130',
    target_type: 'company',
    target_value: 'cmp-nutopia-pilot',
  },
  {
    id: 'tgt-2',
    release_id: 'rel-win-pilot-130',
    target_type: 'device',
    target_value: 'dev-pilot-auth-01',
  },
  {
    id: 'tgt-3',
    release_id: 'rel-win-rollout0-131',
    target_type: 'company',
    target_value: 'cmp-nutopia-pilot',
  },
];

function buildTestApp(): Express {
  const app = express();
  app.use(express.json());

  // Mount real controller routers
  app.use('/api/v1/releases', releaseRouter);
  app.use('/api/v1/updates', updateRouter);
  app.use('/api/v1/admin', adminRouter);

  return app;
}

async function runHttpTests() {
  console.log('===============================================================');
  console.log('🚀 STAGE 10.12.9: GERÇEK EXPRESS HTTP ENTEGRASYON DENETİMİ');
  console.log('===============================================================\n');

  // Intercept pgPool.query and pgPool.connect to serve mock database state cleanly and safely
  const originalQuery = pgPool.query.bind(pgPool);
  const originalConnect = pgPool.connect.bind(pgPool);

  const mockClient = {
    query: (sql: string, params: any[]) => (pgPool as any).query(sql, params),
    release: () => {},
  };
  (pgPool as any).connect = async () => mockClient;

  (pgPool as any).query = async (sql: string, params: any[] = []) => {
    const s = sql.toLowerCase();

    // 1. releases check query: SELECT av.*, (SELECT COUNT(*) FROM update_targets...)
    if (s.includes('from app_versions av') && s.includes('av.platform = $1') && s.includes('av.channel = $2')) {
      const platform = params[0];
      const channel = params[1];
      const matched = mockReleases
        .filter(r => r.platform === platform && r.channel === channel && r.status === 'active')
        .map(r => ({
          ...r,
          target_count: mockTargets.filter(t => t.release_id === r.id).length.toString(),
        }));
      return { rows: matched };
    }

    // 2. update_targets check: SELECT id FROM update_targets WHERE release_id = $1 AND ...
    if (s.includes('select id from update_targets') && s.includes('release_id = $1')) {
      const releaseId = params[0];
      const companyVal = params[1];
      const deviceVal = params[2];
      const matched = mockTargets.filter(t => {
        if (t.release_id !== releaseId) return false;
        if (t.target_type === 'company' && companyVal && t.target_value === companyVal) return true;
        if (t.target_type === 'device' && deviceVal && t.target_value === deviceVal) return true;
        return false;
      });
      return { rows: matched };
    }

    // 3. update_targets count: SELECT COUNT(*) as c FROM update_targets WHERE release_id = $1
    if (s.includes('count(*)') && s.includes('from update_targets where release_id = $1')) {
      const releaseId = params[0];
      const count = mockTargets.filter(t => t.release_id === releaseId).length;
      return { rows: [{ c: count.toString(), count: count.toString() }] };
    }

    // 4. legacy version download: FROM app_versions WHERE platform = $1 AND version_code = $2 AND channel = 'stable'
    if (s.includes('from app_versions') && s.includes('version_code = $2')) {
      const platform = params[0];
      const version = params[1];
      const matched = mockReleases
        .filter(r => r.platform === platform && r.version_code === version && r.channel === 'stable' && r.status === 'active')
        .filter(r => mockTargets.filter(t => t.release_id === r.id).length === 0);
      return { rows: matched };
    }

    // 5. legacy updates check: FROM app_versions WHERE platform = $1 AND status = 'active' AND channel = 'stable' AND (COUNT(update_targets) = 0)
    if (s.includes('from app_versions') && s.includes("channel = 'stable'") && s.includes('count(*) from update_targets')) {
      const platform = params[0];
      const matched = mockReleases
        .filter(r => r.platform === platform && r.channel === 'stable' && r.status === 'active')
        .filter(r => mockTargets.filter(t => t.release_id === r.id).length === 0);
      return { rows: matched };
    }

    // 6. single release check: SELECT * FROM app_versions WHERE id = $1 AND status = 'active'
    if (s.includes('from app_versions where id = $1 and status = \'active\'')) {
      const id = params[0];
      const matched = mockReleases.filter(r => r.id === id && r.status === 'active');
      return { rows: matched };
    }

    // 7. single release check: SELECT * FROM app_versions WHERE version_code = $1
    if (s.includes('from app_versions where version_code = $1')) {
      const ver = params[0];
      const matched = mockReleases.filter(r => r.version_code === ver);
      return { rows: matched };
    }

    // 8. Auth check: SELECT is_active, token_version FROM users WHERE id = $1
    if (s.includes('from users where id = $1')) {
      return { rows: [{ is_active: true, token_version: 1 }] };
    }

    // 9. License check: license_entitlements
    if (s.includes('from license_entitlements where company_id = $1')) {
      return { rows: [{ id: 'lic-1', plan_id: 'serenut-pro', status: 'active' }] };
    }

    // 9. Admin update targets insert / delete / select
    if (s.includes('insert into update_targets')) {
      const id = params[0];
      const releaseId = params[1];
      const targetType = s.includes("'company'") ? 'company' : s.includes("'license_tier'") ? 'license_tier' : 'device';
      const targetVal = params[2];
      mockTargets.push({ id, release_id: releaseId, target_type: targetType, target_value: targetVal });
      return { rowCount: 1, rows: [] };
    }

    if (s.includes('delete from update_targets')) {
      return { rowCount: 1, rows: [] };
    }

    if (s.includes('update app_versions set channel = $2')) {
      return { rowCount: 1, rows: [] };
    }

    if (s.includes('select id, target_type, target_value, created_at from update_targets where release_id = $1')) {
      const releaseId = params[0];
      const matched = mockTargets.filter(t => t.release_id === releaseId);
      return { rows: matched };
    }

    // Default fallback
    return { rows: [] };
  };

  const app = buildTestApp();

  let passedTests = 0;
  let totalTests = 0;

  function record(desc: string, passed: boolean, extra = '') {
    totalTests++;
    if (passed) {
      passedTests++;
      console.log(`✅ PASS: ${desc} ${extra}`);
    } else {
      console.error(`❌ FAIL: ${desc} ${extra}`);
    }
  }

  // Tokens for testing
  const validNutopiaToken = createToken({
    id: 'usr-1',
    email: 'pilot@nutopia.com',
    company_id: 'cmp-nutopia-pilot',
    roles: ['admin'],
  });

  const foreignAttackerToken = createToken({
    id: 'usr-2',
    email: 'attacker@foreign.com',
    company_id: 'cmp-foreign-attacker',
    roles: ['user'],
  });

  const sysadminToken = createToken({
    id: 'usr-sys',
    email: 'sysadmin@serenut.com',
    company_id: 'cmp-system',
    roles: ['sysadmin'],
  });

  try {
    // -------------------------------------------------------------------------
    // TEST 1: Geçerli JWT + Doğru Şirket + Yetkili Cihaz -> 200 OK (Güncelleme Alır)
    // -------------------------------------------------------------------------
    const res1 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.2.0',
        company_id: 'cmp-nutopia-pilot',
        device_activation_id: 'dev-pilot-auth-01',
      })
      .set('Authorization', `Bearer ${validNutopiaToken}`);

    assert.equal(res1.status, 200);
    assert.equal(res1.body.hasUpdate, true);
    assert.equal(res1.body.latestVersion, '1.3.0');
    assert.equal(res1.body.channel, 'pilot');
    record('1. Geçerli JWT ve hedef şirket/cihaz pilot güncellemeyi alır', res1.body.hasUpdate === true);

    // -------------------------------------------------------------------------
    // TEST 2: JWT Olmadan Şirket Beyanı (Token Yok) -> 200 OK, hasUpdate: false (Fail-Closed)
    // -------------------------------------------------------------------------
    const res2 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.2.0',
        company_id: 'cmp-nutopia-pilot', // Query'de beyan ediyor ama token yok
      });

    assert.equal(res2.status, 200);
    assert.equal(res2.body.hasUpdate, false);
    record('2. Token olmadan beyan edilen company_id hedefli güncellemeyi alamaz (Fail-Closed)', res2.body.hasUpdate === false);

    // -------------------------------------------------------------------------
    // TEST 3: Geçersiz / Süresi Dolmuş JWT -> 401 Unauthorized
    // -------------------------------------------------------------------------
    const res3 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.2.0',
        company_id: 'cmp-nutopia-pilot',
      })
      .set('Authorization', 'Bearer invalid-expired-malformed-token');

    assert.equal(res3.status, 401);
    assert.equal(res3.body.error, 'invalid_token');
    record('3. Geçersiz JWT doğrudan HTTP 401 ile reddedilir', res3.status === 401 && res3.body.error === 'invalid_token');

    // -------------------------------------------------------------------------
    // TEST 4: Tenant Mismatch (Query Şirket A, Token Şirket B) -> 401 Unauthorized
    // -------------------------------------------------------------------------
    const res4 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.2.0',
        company_id: 'cmp-nutopia-pilot', // Attacker claims to be Nutopia in query
      })
      .set('Authorization', `Bearer ${foreignAttackerToken}`); // But token belongs to foreign company

    assert.equal(res4.status, 401);
    assert.equal(res4.body.error, 'tenant_mismatch');
    record('4. Token ile query company_id uyuşmazlığı 401 tenant_mismatch ile engellenir', res4.status === 401 && res4.body.error === 'tenant_mismatch');

    // -------------------------------------------------------------------------
    // TEST 5: Hedefi Belirlenmemiş Pilot Sürüm (target_count = 0) -> hasUpdate: false (Fail-Closed)
    // -------------------------------------------------------------------------
    // rel-win-notargets-132 has 0 targets
    const res5 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.3.1', // Asking for updates above 1.3.1 where only 1.3.2 (0 targets) exists
      })
      .set('Authorization', `Bearer ${validNutopiaToken}`);

    assert.equal(res5.status, 200);
    assert.equal(res5.body.hasUpdate, false);
    record('5. Hedefi belirlenmemiş pilot sürüm (0 targets) kamuya sızdırılamaz (Fail-Closed)', res5.body.hasUpdate === false);

    // -------------------------------------------------------------------------
    // TEST 6: Rollout %0 İken Sürüm Dağıtımı Kilitlenir -> hasUpdate: false
    // -------------------------------------------------------------------------
    // rel-win-rollout0-131 has rollout_percentage = 0
    const res6 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.3.0',
        company_id: 'cmp-nutopia-pilot',
        device_activation_id: 'dev-pilot-auth-01',
      })
      .set('Authorization', `Bearer ${validNutopiaToken}`);

    // Candidate 1.3.1 has rollout = 0%, so it must be skipped, leaving hasUpdate: false
    assert.equal(res6.status, 200);
    assert.equal(res6.body.hasUpdate, false);
    record('6. Rollout %0 iken tüm cihazlar için dağıtım kesinlikle engellenir', res6.body.hasUpdate === false);

    // -------------------------------------------------------------------------
    // TEST 7: Paused veya Revoked Sürüm Kontrolde Görünmez -> hasUpdate: false
    // -------------------------------------------------------------------------
    // rel-win-paused-133 has status = 'paused'
    const res7 = await request(app)
      .get('/api/v1/releases/check')
      .query({
        platform: 'windows',
        channel: 'pilot',
        current_version: '1.3.2',
      })
      .set('Authorization', `Bearer ${validNutopiaToken}`);

    assert.equal(res7.status, 200);
    assert.equal(res7.body.hasUpdate, false);
    record('7. Paused/Revoked durumdaki sürüm güncelleme kontrolünde sunulmaz', res7.body.hasUpdate === false);

    // -------------------------------------------------------------------------
    // TEST 8: Eski İstemci /updates/check Hedefli Sürümü Göremez
    // -------------------------------------------------------------------------
    const res8 = await request(app)
      .get('/api/v1/updates/check')
      .query({
        platform: 'windows',
        current_version: '1.1.0',
      });

    assert.equal(res8.status, 200);
    assert.equal(res8.body.latestVersion, '1.2.0'); // Sees 1.2.0 (stable, 0 targets), never 1.3.0 (pilot)
    record('8. Eski /updates/check hedefli pilot sürümleri asla göstermez', res8.body.latestVersion === '1.2.0');

    // -------------------------------------------------------------------------
    // TEST 9: Eski /updates/download/.../version/1.3.0 Hedefli Sürüm İçin 404 Verir
    // -------------------------------------------------------------------------
    const res9 = await request(app)
      .get('/api/v1/updates/download/windows/version/1.3.0');

    assert.equal(res9.status, 404);
    assert.equal(res9.body.error, 'release_not_found');
    record('9. Eski versiyon indirme uç noktası hedefli sürüm için 404 döner', res9.status === 404);

    // -------------------------------------------------------------------------
    // TEST 10: Doğrudan İndirme Uç Noktasında Yetkisiz Şirket 403 Forbidden Alır
    // -------------------------------------------------------------------------
    const res10 = await request(app)
      .get('/api/v1/releases/download/rel-win-pilot-130')
      .set('Authorization', `Bearer ${foreignAttackerToken}`); // Attacker company

    assert.equal(res10.status, 403);
    assert.equal(res10.body.error, 'unauthorized_target');
    record('10. Doğrudan indirme URL si yetkisiz şirket için 403 unauthorized_target verir', res10.status === 403 && res10.body.error === 'unauthorized_target');

    // -------------------------------------------------------------------------
    // TEST 11: Durdurulmuş (Paused) Sürümü İndirme Denemesi 404 Verir
    // -------------------------------------------------------------------------
    const res11 = await request(app)
      .get('/api/v1/releases/download/rel-win-paused-133')
      .set('Authorization', `Bearer ${validNutopiaToken}`);

    assert.equal(res11.status, 404);
    assert.equal(res11.body.error, 'release_not_found');
    record('11. Durdurulmuş (paused/revoked) sürümün önceden edinilmiş URL si 404 verir', res11.status === 404 && res11.body.error === 'release_not_found');

    // -------------------------------------------------------------------------
    // TEST 12: Admin Pilot Dağıtımında Hedef Şirket Yoksa 400 ile Reddedilir
    // -------------------------------------------------------------------------
    const res12 = await request(app)
      .post('/api/v1/admin/releases/distribute')
      .set('Authorization', `Bearer ${sysadminToken}`)
      .send({
        version: '1.3.0',
        channel: 'pilot',
        target_tenants: [], // Empty targets on pilot channel
      });

    assert.equal(res12.status, 400);
    assert.equal(res12.body.error, 'pilot_requires_targets');
    record('12. Admin panelinde pilot yayını için hedef şirket zorunludur (400 pilot_requires_targets)', res12.status === 400 && res12.body.error === 'pilot_requires_targets');

    // -------------------------------------------------------------------------
    // TEST 13: Admin Hedefleri Kaydeder ve GET /releases/:version/targets ile Okur
    // -------------------------------------------------------------------------
    const res13Post = await request(app)
      .post('/api/v1/admin/releases/distribute')
      .set('Authorization', `Bearer ${sysadminToken}`)
      .send({
        version: '1.3.0',
        channel: 'pilot',
        target_tenants: ['cmp-nutopia-pilot'],
        target_tiers: ['pro'],
        rollout_percentage: 50,
      });

    assert.equal(res13Post.status, 200);
    assert.equal(res13Post.body.success, true);

    const res13Get = await request(app)
      .get('/api/v1/admin/releases/1.3.0/targets')
      .set('Authorization', `Bearer ${sysadminToken}`);

    assert.equal(res13Get.status, 200);
    assert.equal(res13Get.body.version, '1.3.0');
    assert.ok(res13Get.body.target_tenants.includes('cmp-nutopia-pilot'));
    record('13. Admin hedefleri kaydeder ve GET /releases/:version/targets ile eksiksiz okur', res13Get.status === 200 && res13Get.body.target_tenants.includes('cmp-nutopia-pilot'));

    // -------------------------------------------------------------------------
    // TEST 14: Yetkisiz Kullanıcı Admin Dağıtım veya Hedef Okuma Yapamaz (401/403)
    // -------------------------------------------------------------------------
    const res14 = await request(app)
      .get('/api/v1/admin/releases/1.3.0/targets')
      .set('Authorization', `Bearer ${foreignAttackerToken}`); // Non-admin user

    assert.ok(res14.status === 401 || res14.status === 403);
    record('14. Yetkisiz kullanıcı admin hedef listesini okuyamaz (401/403)', res14.status === 401 || res14.status === 403);

    // -------------------------------------------------------------------------
    // TEST 15: Hassas Bilgi Sızıntısı Denetimi (Stack Trace / DB Sızıntısı Yok)
    // -------------------------------------------------------------------------
    const errorResponses = [res3.body, res4.body, res9.body, res10.body, res11.body, res12.body];
    let leaksSensitive = false;
    for (const body of errorResponses) {
      const raw = JSON.stringify(body);
      if (raw.includes('postgres') || raw.includes('SELECT') || raw.includes('password') || raw.includes('stack')) {
        leaksSensitive = true;
      }
    }
    record('15. Hata yanıtlarında stack trace veya veritabanı sızıntısı bulunmaz (Clean JSON)', !leaksSensitive);

  } finally {
    // Restore original pgPool.query and pgPool.connect
    (pgPool as any).query = originalQuery;
    (pgPool as any).connect = originalConnect;
  }

  console.log('\n===============================================================');
  console.log(`🎉 TOPLAM TEST: ${totalTests} | BAŞARILI: ${passedTests} | BAŞARISIZ: ${totalTests - passedTests}`);
  console.log('===============================================================\n');

  if (passedTests !== totalTests) {
    process.exit(1);
  }
}

runHttpTests().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});

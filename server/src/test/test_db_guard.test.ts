// server/src/test/test_db_guard.test.ts
// SERENUT OS — STAGE 10.7.4.2 POSTGRESQL FAIL-CLOSED KORUMA BİRİM TESTLERİ
//
// Bu test süiti GERÇEK BİR VERİTABANINA BAĞLANMAZ.
// Statik analiz ve kontrollü sahte (fake) istemciler ile fail-closed korumasının
// 14 zorunlu senaryosunu sıfır yıkıcı etkiyle doğrular.

import {
  validateTestDatabaseUrl,
  assertSafeTestEnvironment,
  assertIsolatedTestDatabase,
} from '../config/test-db-guard';

let totalTests = 0;
let passedTests = 0;

function assert(condition: boolean, message: string) {
  totalTests++;
  if (!condition) {
    console.error(`❌ TEST FAILED: ${message}`);
    throw new Error(`Assertion failed: ${message}`);
  }
  passedTests++;
  console.log(`✅ PASS: ${message}`);
}

async function runUnitTests() {
  console.log('====================================================');
  console.log('🛡️  STAGE 10.7.4.2: TEST-DB-GUARD 14 SENARYO TESTİ');
  console.log('====================================================\n');

  // Senaryo 1: Güvenli test yapılandırması (Doğru NODE_ENV ve onaylı test URL)
  {
    const res = validateTestDatabaseUrl('postgres://postgres:postgres@127.0.0.1:5432/serenut_test');
    assert(res.isValid, '1.1: Geçerli test URL onaylanmalı');
    assert(res.databaseName === 'serenut_test', '1.2: Veritabanı adı serenut_test olmalı');

    const envRes = assertSafeTestEnvironment({
      nodeEnv: 'test',
      connectionString: 'postgres://localhost:5432/serenut_test',
    });
    assert(envRes.databaseName === 'serenut_test', '1.3: Güvenli test ortamı onaylanmalı');
  }

  // Senaryo 2: Eksik NODE_ENV
  {
    let threw = false;
    try {
      assertSafeTestEnvironment({ nodeEnv: undefined, connectionString: 'postgres://localhost/serenut_test' });
    } catch (e: any) {
      threw = true;
      assert(e.message.includes('NODE_ENV'), '2.1: Eksik NODE_ENV fail-closed ile durdurulmalı');
    }
    assert(threw, '2.2: Eksik NODE_ENV durumunda izin verilmemeli');
  }

  // Senaryo 3: NODE_ENV=development
  {
    let threw = false;
    try {
      assertSafeTestEnvironment({ nodeEnv: 'development', connectionString: 'postgres://localhost/serenut_test' });
    } catch (e: any) {
      threw = true;
      assert(e.message.includes('development'), '3.1: NODE_ENV development iken reddedilmeli');
    }
    assert(threw, '3.2: Development ortamında test çalışması engellenmeli');
  }

  // Senaryo 4: Eksik test veritabanı URL'si
  {
    const emptyRes = validateTestDatabaseUrl('');
    assert(!emptyRes.isValid, '4.1: Boş URL geçersiz sayılmalı');
    assert(emptyRes.error!.includes('DATABASE_URL_EMPTY'), '4.2: DATABASE_URL_EMPTY hatası üretilmeli');

    const undefRes = validateTestDatabaseUrl(undefined);
    assert(!undefRes.isValid, '4.3: Tanımsız (undefined) URL geçersiz sayılmalı');
  }

  // Senaryo 5: Bozuk veya geçersiz protokol URL
  {
    const malformed1 = validateTestDatabaseUrl('http://localhost:5432/serenut_test');
    assert(!malformed1.isValid, '5.1: http:// protokolü reddedilmeli');
    assert(malformed1.error!.includes('INVALID_PROTOCOL'), '5.2: INVALID_PROTOCOL hatası üretilmeli');

    const malformed2 = validateTestDatabaseUrl('not_a_valid_url_string');
    assert(!malformed2.isValid, '5.3: Düzensiz dize reddedilmeli');
    assert(malformed2.error!.includes('DATABASE_URL_MALFORMED'), '5.4: DATABASE_URL_MALFORMED hatası üretilmeli');

    const malformed3 = validateTestDatabaseUrl('postgres://localhost:5432/');
    assert(!malformed3.isValid, '5.5: Veritabanı adı olmayan URL reddedilmeli');
    assert(malformed3.error!.includes('DATABASE_NAME_MISSING'), '5.6: DATABASE_NAME_MISSING hatası üretilmeli');
  }

  // Senaryo 6: Üretim veritabanı adı
  {
    for (const prodName of ['production', 'prod_db', 'serenut_prod', 'prod']) {
      const res = validateTestDatabaseUrl(`postgres://user:pass@127.0.0.1:5432/${prodName}`);
      assert(!res.isValid, `6.1: Üretim veritabanı '${prodName}' reddedilmeli`);
      assert(res.error!.includes('FORBIDDEN_DATABASE_IDENTIFIER'), `6.2: '${prodName}' için kara liste hatası üretilmeli`);
    }
  }

  // Senaryo 7: Geliştirme veritabanı adı (nutopiano, serenut_dev)
  {
    for (const devName of ['nutopiano', 'serenut_dev']) {
      const res = validateTestDatabaseUrl(`postgres://postgres:postgres@localhost:5432/${devName}`);
      assert(!res.isValid, `7.1: Geliştirme veritabanı '${devName}' reddedilmeli`);
      assert(res.error!.includes('FORBIDDEN_DATABASE_IDENTIFIER'), `7.2: '${devName}' için kara liste koruması devreye girmeli`);
    }
  }

  // Senaryo 8: Yasaklı ana makine veya bağlantı hedefi (Supabase, AWS RDS, serenut.com)
  {
    for (const host of ['aws.rds.amazonaws.com', 'db.supabase.co', 'api.serenut.com']) {
      const res = validateTestDatabaseUrl(`postgres://user:pass@${host}:5432/serenut_test`);
      assert(!res.isValid, `8.1: Yasaklı host '${host}' içeren URL reddedilmeli`);
      assert(res.error!.includes('FORBIDDEN_DATABASE_IDENTIFIER'), `8.2: '${host}' için kara liste devreye girmeli`);
    }
  }

  // Senaryo 9: İzin verilen test adıyla gizlenmiş yasaklı hedef (nutopiano_test veya localhost/nutopiano_test)
  {
    const disguised1 = validateTestDatabaseUrl('postgres://localhost:5432/nutopiano_test');
    assert(!disguised1.isValid, '9.1: nutopiano_test gibi gizlenmiş ad reddedilmeli');
    assert(disguised1.error!.includes('FORBIDDEN_DATABASE_IDENTIFIER'), '9.2: nutopiano ifadesi test son eki olsa dahi engellenmeli');

    const disguised2 = validateTestDatabaseUrl('postgres://rds.amazonaws.com:5432/my_ci_test');
    assert(!disguised2.isValid, '9.3: RDS üzerindeki test veritabanı reddedilmeli');
  }

  // Senaryo 10: current_database() sonucunun beklenenden farklı olması
  {
    const fakeClientMismatch = {
      query: async (sql: string) => ({ rows: [{ db_name: 'different_ci_test' }] }),
    };
    let threw = false;
    try {
      await assertIsolatedTestDatabase(fakeClientMismatch, 'serenut_test');
    } catch (e: any) {
      threw = true;
      assert(e.message.includes('Beklenen test veritabanı'), '10.1: İsim uyuşmazlığı tespit edilmeli');
    }
    assert(threw, '10.2: Beklenmeyen veritabanı döndüğünde işlem durdurulmalı');
  }

  // Senaryo 11: Fiziksel veritabanı doğrulamasının başarısız olması (Boş veya null dönmesi)
  {
    const fakeClientEmpty = {
      query: async (sql: string) => ({ rows: [] }),
    };
    let threw = false;
    try {
      await assertIsolatedTestDatabase(fakeClientEmpty, 'serenut_test');
    } catch (e: any) {
      threw = true;
      assert(e.message.includes('current_database() sorgusundan veritabanı adı alınamadı'), '11.1: Boş yanıtta fail-closed olmalı');
    }
    assert(threw, '11.2: Boş veritabanı adı kesinlikle reddedilmeli');
  }

  // Senaryo 12: Veritabanı bağlantı hatası (Socket/Connection Error)
  {
    const fakeClientConnError = {
      query: async (sql: string) => {
        throw new Error('connect ECONNREFUSED 127.0.0.1:5432');
      },
    };
    let threw = false;
    try {
      await assertIsolatedTestDatabase(fakeClientConnError, 'serenut_test');
    } catch (e: any) {
      threw = true;
      assert(e.message.includes('ECONNREFUSED'), '12.1: Bağlantı hatası yukarı fırlatılmalı');
    }
    assert(threw, '12.2: Bağlantı hatasında işlem sürdürülmemeli');
  }

  // Senaryo 13: Doğrulama öncesinde yıkıcı SQL çalıştırılmaya teşebbüs edilmesi
  {
    const queryLog: string[] = [];
    const guardedClient = {
      query: async (sql: string) => {
        queryLog.push(sql);
        if (sql.includes('current_database')) {
          // İstemci fiziksel olarak 'nutopiano' döndürsün
          return { rows: [{ db_name: 'nutopiano' }] };
        }
        return { rows: [] };
      },
    };

    let reachedDropSchema = false;
    try {
      await assertIsolatedTestDatabase(guardedClient, 'serenut_test');
      // Bu satıra ASLA ulaşılmamalı!
      await guardedClient.query('DROP SCHEMA public CASCADE');
      reachedDropSchema = true;
    } catch (e: any) {
      // Beklenen abort
    }

    assert(!reachedDropSchema, '13.1: DROP SCHEMA satırına ASLA ulaşılamamalı');
    assert(!queryLog.some((q) => q.includes('DROP SCHEMA')), '13.2: DROP SCHEMA sorgusu istemciye iletilmemiş olmalı');
    assert(queryLog[0].includes('current_database'), '13.3: Yalnızca güvenlik denetim sorgusu çalıştırılmış olmalı');
  }

  // Senaryo 14: Korumanın hata durumunda varsayılan olarak izin vermemesi (Default Fail-Closed)
  {
    let defaultFailClosed = false;
    try {
      // Bilinmeyen veya tanımsız tüm parametrelerde varsayılan ret
      assertSafeTestEnvironment({ nodeEnv: 'unknown_env', connectionString: '' });
    } catch (e: any) {
      defaultFailClosed = true;
    }
    assert(defaultFailClosed, '14.1: Tanımsız veya beklenmeyen durumda varsayılan FAIL-CLOSED olmalı');
  }

  console.log('\n====================================================');
  console.log(`🎉 14 ZORUNLU SENARYO TAMAMLANDI: ${passedTests}/${totalTests} BAŞARILI`);
  console.log('====================================================\n');
}

// Node ortamında test ortamı simülasyonuyla çalıştır
process.env.NODE_ENV = 'test';
process.env.TEST_DATABASE_URL = 'postgres://postgres:postgres@127.0.0.1:5432/serenut_test';

runUnitTests().catch((err) => {
  console.error('Fatal test runner failure:', err);
  process.exit(1);
});

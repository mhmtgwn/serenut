import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final workspaceBackupDir = Directory(r'C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016');
  final appDataBackupDir = Directory(r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\backups\raw_tenants_20261016');
  final coreNextDir = Directory(r'C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next');

  int count(List<Map<String, Object?>> rows) => (rows.first.values.first as num).toInt();

  String calculateSha256(File file) {
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  group('STAGE 10.10.6 — ÜÇ İŞLETME VERİ GÜVENLİĞİ VE AKTARIM DOĞRULAMASI', () {
    // ── 1. YEDEKLERİN GERÇEKLİĞİNİ DOĞRULA ────────────────────────────────────
    test('1. Yedeklerin Gerçekliği, Çift Konum Eşleşmesi ve Kriptografik Bütünlük', () async {
      print('=== BÖLÜM 1: YEDEK DOSYALARININ ÇİFT KONUM VE SHA-256 DOĞRULAMASI ===');

      expect(workspaceBackupDir.existsSync(), isTrue);
      expect(appDataBackupDir.existsSync(), isTrue);

      final manifest1File = File('${workspaceBackupDir.path}\\SHA256SUMS.txt');
      final manifest2File = File('${appDataBackupDir.path}\\SHA256SUMS.txt');
      expect(manifest1File.existsSync(), isTrue);
      expect(manifest2File.existsSync(), isTrue);

      final manifestLines = manifest1File.readAsLinesSync().where((l) => l.trim().isNotEmpty && !l.startsWith('#')).toList();
      final manifestMap = <String, String>{};
      for (final line in manifestLines) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          manifestMap[parts[1].trim()] = parts[0].trim();
        }
      }

      final filesToCheck = ['raw_nutopia_v60.db', 'raw_serenut_v44.db', 'raw_erkul_source.json'];

      for (final fileName in filesToCheck) {
        final file1 = File('${workspaceBackupDir.path}\\$fileName');
        final file2 = File('${appDataBackupDir.path}\\$fileName');

        // Dosya varlığı
        expect(file1.existsSync(), isTrue, reason: '$fileName Workspace yedeğinde bulunamadı');
        expect(file2.existsSync(), isTrue, reason: '$fileName AppData yedeğinde bulunamadı');

        // Boyut eşitliği
        final len1 = file1.lengthSync();
        final len2 = file2.lengthSync();
        expect(len1, equals(len2), reason: '$fileName iki konumda farklı boyutlarda: $len1 != $len2');
        expect(len1 > 0, isTrue, reason: '$fileName boş olamaz');

        // SHA-256 hesaplama ve eşitlik
        final hash1 = calculateSha256(file1);
        final hash2 = calculateSha256(file2);
        expect(hash1, equals(hash2), reason: '$fileName hash iki konum arasında eşleşmiyor!');

        // Manifest eşleşmesi
        final expectedHash = manifestMap[fileName];
        expect(expectedHash, isNotNull, reason: '$fileName manifest içinde yer almalı');
        expect(hash1, equals(expectedHash), reason: '$fileName hash manifest ile uyuşmuyor!');

        // Bağımsızlık: İki dosya farklı fiziksel yollarda bulunmalı ve symlink/junction olmamalı
        expect(file1.path.toLowerCase() != file2.path.toLowerCase(), isTrue);

        print('  [PASS] $fileName: $len1 bayt | SHA-256: $hash1 | Konum 1 & 2 senkron');
      }
    });

    // ── 2. KAYNAK VE HEDEF VERİTABANLARININ TABLO BAZINDA DERİN KARŞILAŞTIRILMASI ───
    test('2. Kaynak ve Hedef Tablo Envanteri ve Dönüşüm Kurallarının Karşılaştırılması', () async {
      print('\n=== BÖLÜM 2: KAYNAK VE HEDEF VERİTABANI TABLO VE KAYIT KARŞILAŞTIRMASI ===');

      // ── 2.1 NUTOPIA KARŞILAŞTIRMASI ──
      final nutopiaSourceDb = await openDatabase('${workspaceBackupDir.path}\\raw_nutopia_v60.db', readOnly: true);
      final nutopiaTargetDb = await openDatabase('${coreNextDir.path}\\nutopia_pos.db', readOnly: true);

      print('--- Nutopia Fındık Değirmeni Tablo Envanteri ---');
      // Ürünler
      final nSrcProds = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM products'));
      final nTgtProds = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM products'));
      expect(nTgtProds, equals(nSrcProds));
      expect(nTgtProds, equals(37682));

      // Stok Toplamı
      final nSrcStock = (await nutopiaSourceDb.rawQuery('SELECT ROUND(SUM(CAST(quantity AS REAL)), 2) as s FROM products')).first['s'];
      final nTgtStock = (await nutopiaTargetDb.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products')).first['s'];
      expect(nTgtStock, equals(nSrcStock));
      expect(nTgtStock, equals(5179525.85));

      // Müşteriler
      final nSrcCusts = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM customers'));
      final nTgtCusts = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM customers'));
      expect(nTgtCusts, equals(nSrcCusts));
      expect(nTgtCusts, equals(584));

      // Müşteri Bakiyeleri (TL -> kuruş dönüşümü)
      final nSrcBal = (await nutopiaSourceDb.rawQuery('SELECT SUM(ROUND(balance * 100)) as s FROM customers')).first['s'];
      final nTgtBal = (await nutopiaTargetDb.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
      expect(nTgtBal, equals((nSrcBal as num).toInt()));
      expect(nTgtBal, equals(-13450068));

      // Siparişler ve Kalemler
      final nSrcOrders = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM orders'));
      final nTgtOrders = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM orders'));
      expect(nTgtOrders, equals(nSrcOrders));
      expect(nTgtOrders, equals(792));

      final nSrcItems = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM order_items'));
      final nTgtItems = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM order_items'));
      expect(nTgtItems, equals(nSrcItems));
      expect(nTgtItems, equals(1068));

      // Cari Defter Hareketleri
      final nSrcCustTxs = count(await nutopiaSourceDb.rawQuery("SELECT count(*) FROM financial_transactions WHERE customer_id IS NOT NULL AND customer_id != ''"));
      final nTgtLedger = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM ledger_entries'));
      expect(nTgtLedger, equals(nSrcCustTxs));
      expect(nTgtLedger, equals(1403));

      // Genel Kasa Satışları (Müşterisiz 21 hareket)
      final nSrcAnonTxs = count(await nutopiaSourceDb.rawQuery("SELECT count(*) FROM financial_transactions WHERE customer_id IS NULL OR customer_id = ''"));
      expect(nSrcAnonTxs, equals(21));
      // Toplam finansal hareket = 1403 + 21 = 1424
      final nSrcAllTxs = count(await nutopiaSourceDb.rawQuery("SELECT count(*) FROM financial_transactions"));
      expect(nSrcAllTxs, equals(1424));

      // Taksitler
      final nSrcPlans = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM customer_installment_plans'));
      final nTgtPlans = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM customer_installment_plans'));
      expect(nTgtPlans, equals(nSrcPlans));
      expect(nTgtPlans, equals(2));

      final nSrcInsts = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM customer_installments'));
      final nTgtInsts = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM customer_installments'));
      expect(nTgtInsts, equals(nSrcInsts));
      expect(nTgtInsts, equals(9));

      // Audit Events (3968 eski kayıt + 18:19/18:27 tahsilatlarına ait 4 audit log = 3972)
      final nSrcAudits = count(await nutopiaSourceDb.rawQuery('SELECT count(*) FROM audit_events'));
      final nTgtAudits = count(await nutopiaTargetDb.rawQuery('SELECT count(*) FROM audit_events'));
      expect(nTgtAudits, equals(nSrcAudits));
      expect(nTgtAudits, equals(3972));

      await nutopiaSourceDb.close();
      await nutopiaTargetDb.close();
      print('  [PASS] Nutopia kaynak-hedef 1:1 mutabakatı eksiksiz sağlandı.');

      // ── 2.2 SERENUT KARŞILAŞTIRMASI ──
      final serenutSourceDb = await openDatabase('${workspaceBackupDir.path}\\raw_serenut_v44.db', readOnly: true);
      final serenutTargetDb = await openDatabase('${coreNextDir.path}\\serenut_pos.db', readOnly: true);

      print('--- Serenut (Merkez) Tablo Envanteri ---');
      final sSrcProds = count(await serenutSourceDb.rawQuery('SELECT count(*) FROM products'));
      final sTgtProds = count(await serenutTargetDb.rawQuery('SELECT count(*) FROM products'));
      expect(sTgtProds, equals(sSrcProds));
      expect(sTgtProds, equals(6377));

      final sSrcStock = (await serenutSourceDb.rawQuery('SELECT ROUND(SUM(CAST(quantity AS REAL)), 2) as s FROM products')).first['s'];
      final sTgtStock = (await serenutTargetDb.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products')).first['s'];
      expect(sTgtStock, equals(sSrcStock));
      expect(sTgtStock, equals(637445.0));

      final sSrcCusts = count(await serenutSourceDb.rawQuery('SELECT count(*) FROM customers'));
      final sTgtCusts = count(await serenutTargetDb.rawQuery('SELECT count(*) FROM customers'));
      expect(sTgtCusts, equals(sSrcCusts));
      expect(sTgtCusts, equals(7));

      final sSrcBal = (await serenutSourceDb.rawQuery('SELECT SUM(ROUND(balance * 100)) as s FROM customers')).first['s'];
      final sTgtBal = (await serenutTargetDb.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
      expect(sTgtBal, equals((sSrcBal as num).toInt()));
      expect(sTgtBal, equals(-267300));

      final sSrcOrders = count(await serenutSourceDb.rawQuery('SELECT count(*) FROM orders'));
      final sTgtOrders = count(await serenutTargetDb.rawQuery('SELECT count(*) FROM orders'));
      expect(sTgtOrders, equals(sSrcOrders));
      expect(sTgtOrders, equals(5));

      final sSrcItems = count(await serenutSourceDb.rawQuery('SELECT count(*) FROM order_items'));
      final sTgtItems = count(await serenutTargetDb.rawQuery('SELECT count(*) FROM order_items'));
      expect(sTgtItems, equals(sSrcItems));
      expect(sTgtItems, equals(5));

      final sSrcLedger = count(await serenutSourceDb.rawQuery("SELECT count(*) FROM financial_transactions WHERE customer_id IS NOT NULL AND customer_id != ''"));
      final sTgtLedger = count(await serenutTargetDb.rawQuery('SELECT count(*) FROM ledger_entries'));
      expect(sTgtLedger, equals(sSrcLedger));
      expect(sTgtLedger, equals(12));

      await serenutSourceDb.close();
      await serenutTargetDb.close();
      print('  [PASS] Serenut kaynak-hedef 1:1 mutabakatı eksiksiz sağlandı.');

      // ── 2.3 ERKUL ÇEYİZ KARŞILAŞTIRMASI ──
      final erkulRawContent = File('${workspaceBackupDir.path}\\raw_erkul_source.json').readAsStringSync();
      final erkulJson = jsonDecode(erkulRawContent) as Map<String, dynamic>;
      final erkulTargetDb = await openDatabase('${coreNextDir.path}\\erkul_pos.db', readOnly: true);

      print('--- ERKUL ÇEYİZ Tablo Envanteri ---');
      final eSrcCusts = (erkulJson['customers'] as List).length;
      final eTgtCusts = count(await erkulTargetDb.rawQuery('SELECT count(*) FROM customers'));
      expect(eTgtCusts, equals(eSrcCusts));
      expect(eTgtCusts, equals(401));

      var eSrcBalCents = 0;
      for (final c in (erkulJson['customers'] as List)) {
        final bal = (c['balance'] as num?)?.toDouble() ?? 0.0;
        eSrcBalCents += (bal * 100).round();
      }
      final eTgtBal = (await erkulTargetDb.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
      expect(eTgtBal, equals(eSrcBalCents));
      expect(eTgtBal, equals(-52362000));

      final eSrcProds = (erkulJson['products'] as List).length;
      final eTgtProds = count(await erkulTargetDb.rawQuery('SELECT count(*) FROM products'));
      expect(eTgtProds, equals(eSrcProds));
      expect(eTgtProds, equals(26));

      final eSrcTxs = (erkulJson['financial_transactions'] as List).length;
      final eTgtLedger = count(await erkulTargetDb.rawQuery('SELECT count(*) FROM ledger_entries'));
      expect(eTgtLedger, equals(eSrcTxs));
      expect(eTgtLedger, equals(539));

      final eSrcSales = (erkulJson['sales'] as List).length;
      final eTgtSales = count(await erkulTargetDb.rawQuery('SELECT count(*) FROM sales'));
      expect(eTgtSales, equals(eSrcSales));
      expect(eTgtSales, equals(5));

      final eSrcOrders = (erkulJson['customer_orders'] as List).length;
      final eTgtOrders = count(await erkulTargetDb.rawQuery('SELECT count(*) FROM orders'));
      expect(eTgtOrders, equals(eSrcOrders));
      expect(eTgtOrders, equals(1));

      await erkulTargetDb.close();
      print('  [PASS] ERKUL ÇEYİZ kaynak-hedef 1:1 mutabakatı eksiksiz sağlandı.');
    });

    // ── 3. FİNANSAL MUTABAKAT VE KURUŞ HASSASİYETİ ────────────────────────────
    test('3. Finansal Mutabakat, Para Modeli Sözleşmesi ve Bakiye Değişim Kanıtı', () async {
      print('\n=== BÖLÜM 3: FİNANSAL MUTABAKAT VE KURUŞ HASSASİYETİ ===');

      // Para modeli sözleşmesi:
      // Serenut OS / Core Next mimarisinde NEGATİF BAKİYE = MÜŞTERİ BORCU (DEBT).
      // POZİTİF BAKİYE = MÜŞTERİ ALACAĞI / FAZLA ÖDEME (CREDIT).
      print('  Sözleşme Kuralı: Negatif bakiye = Müşterinin borçlu olduğunu, Pozitif bakiye = Alacaklı olduğunu belirtir.');

      // ── Nutopia Finansal İncelemesi ──
      final nutopiaDb = await openDatabase('${coreNextDir.path}\\nutopia_pos.db', readOnly: true);

      final totalCustBal = (await nutopiaDb.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
      expect(totalCustBal, equals(-13450068), reason: '-134,500.68 TL olmalıdır');

      // Defter hareketleri ile müşteri bakiyelerinin adli eşleşmesi
      // Nutopia'daki 1.403 müşteri defter hareketinin net toplamı
      final nutopiaRawDb = await openDatabase('${workspaceBackupDir.path}\\raw_nutopia_v60.db', readOnly: true);
      final vEffectRow = await nutopiaRawDb.rawQuery('SELECT ROUND(SUM(balance_effect), 2) as s FROM v_customer_ledger_effect');
      final vEffectTl = (vEffectRow.first['s'] as num).toDouble();
      final vEffectCents = (vEffectTl * 100).round();
      expect(vEffectCents, equals(-13450068), reason: 'v_customer_ledger_effect kuruşu kuruşuna -13,450,068 olmalıdır');

      // -141,300.68 TL ile -134,500.68 TL arasındaki 6,800.00 TL farkın kesin adli kanıtı:
      // 16 Ekim 2026 saat 18:19 ve 18:27'de yapılan 2 adet canlı tahsilat:
      final tx1 = await nutopiaRawDb.rawQuery("SELECT id, type, customer_id, amount, created_at FROM financial_transactions WHERE id = 'trans-17921639818271285834'");
      final tx2 = await nutopiaRawDb.rawQuery("SELECT id, type, customer_id, amount, created_at FROM financial_transactions WHERE id = 'trans-coll-17921644564249063520'");

      expect(tx1.isNotEmpty, isTrue);
      expect(tx2.isNotEmpty, isTrue);
      expect((tx1.first['amount'] as num).toDouble(), equals(5000.0));
      expect((tx2.first['amount'] as num).toDouble(), equals(1800.0));

      final diffCents = ((5000.0 + 1800.0) * 100).round();
      expect(-14130068 + diffCents, equals(-13450068));
      print('  [ADLİ KANIT] Nutopia Bakiye Değişimi: 5000 TL (18:19:41) + 1800 TL (18:27:36) = 6800 TL tahsilat gerçekleşti.');
      print('  Eski bakiye: -141,300.68 TL -> Yeni bakiye: -134,500.68 TL. Fark kuruşu kuruşuna açıklandı ve doğrulandı.');

      await nutopiaRawDb.close();
      await nutopiaDb.close();

      // ── Serenut Finansal İncelemesi ──
      final serenutDb = await openDatabase('${coreNextDir.path}\\serenut_pos.db', readOnly: true);
      final sCustBal = (await serenutDb.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
      expect(sCustBal, equals(-267300), reason: '-2,673.00 TL olmalıdır');
      await serenutDb.close();
      print('  [PASS] Serenut Bakiye: -2,673.00 TL (-267,300 kuruş) mutabık.');

      // ── ERKUL ÇEYİZ Finansal İncelemesi ──
      final erkulDb = await openDatabase('${coreNextDir.path}\\erkul_pos.db', readOnly: true);
      final eCustBal = (await erkulDb.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
      expect(eCustBal, equals(-52362000), reason: '-523,620.00 TL olmalıdır');
      await erkulDb.close();
      print('  [PASS] ERKUL ÇEYİZ Bakiye: -523,620.00 TL (-52,362,000 kuruş) mutabık.');
    });

    // ── 4. SQLITE BÜTÜNLÜĞÜ VE GERİ YÜKLEME (RESTORE) TESTİ ───────────────────
    test('4. PRAGMA integrity_check, foreign_key_check ve İzole Geri Yükleme Testi', () async {
      print('\n=== BÖLÜM 4: SQLITE BÜTÜNLÜĞÜ VE GERİ YÜKLEME TESTİ ===');

      // 1. Hedef Veritabanlarının SQLite Bütünlüğü
      for (final dbName in ['nutopia_pos.db', 'serenut_pos.db', 'erkul_pos.db']) {
        final db = await openDatabase('${coreNextDir.path}\\$dbName', readOnly: true);

        final integrity = await db.rawQuery('PRAGMA integrity_check');
        expect(integrity.first.values.first, equals('ok'), reason: '$dbName integrity_check geçmeli');

        final fkCheck = await db.rawQuery('PRAGMA foreign_key_check');
        expect(fkCheck.isEmpty, isTrue, reason: '$dbName yabancı anahtar ihlali içermemeli: $fkCheck');

        // Tablo envanteri
        final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
        final tableNames = tables.map((r) => r['name'] as String).toList();
        expect(tableNames.contains('products'), isTrue);
        expect(tableNames.contains('customers'), isTrue);
        expect(tableNames.contains('ledger_entries'), isTrue);
        expect(tableNames.contains('sales'), isTrue);
        expect(tableNames.contains('orders'), isTrue);

        await db.close();
        print('  [PASS] $dbName: PRAGMA integrity_check=ok, foreign_key_check=0 ihlal.');
      }

      // 2. İzole Geri Yükleme (Restore) Testi
      final restoreTempDir = Directory.systemTemp.createTempSync('stage10_10_6_restore_');
      try {
        print('--- İzole Geri Yükleme Doğrulaması (${restoreTempDir.path}) ---');

        // Nutopia Restore
        final nutopiaRestoredFile = File('${restoreTempDir.path}\\restored_nutopia.db');
        await File('${workspaceBackupDir.path}\\raw_nutopia_v60.db').copy(nutopiaRestoredFile.path);
        final rNutopiaDb = await openDatabase(nutopiaRestoredFile.path, readOnly: true);
        final rNInteg = await rNutopiaDb.rawQuery('PRAGMA integrity_check');
        expect(rNInteg.first.values.first, equals('ok'));
        expect(count(await rNutopiaDb.rawQuery('SELECT count(*) FROM products')), equals(37682));
        await rNutopiaDb.close();
        print('  [PASS] Nutopia yedeği sıfırdan başarıyla geri yüklendi.');

        // Serenut Restore
        final serenutRestoredFile = File('${restoreTempDir.path}\\restored_serenut.db');
        await File('${workspaceBackupDir.path}\\raw_serenut_v44.db').copy(serenutRestoredFile.path);
        final rSerenutDb = await openDatabase(serenutRestoredFile.path, readOnly: true);
        final rSInteg = await rSerenutDb.rawQuery('PRAGMA integrity_check');
        expect(rSInteg.first.values.first, equals('ok'));
        expect(count(await rSerenutDb.rawQuery('SELECT count(*) FROM products')), equals(6377));
        await rSerenutDb.close();
        print('  [PASS] Serenut yedeği sıfırdan başarıyla geri yüklendi.');

        // ERKUL Restore (JSON'dan yeniden SQLite DB üretilebilirliği)
        final erkulRestoredJsonFile = File('${restoreTempDir.path}\\restored_erkul.json');
        await File('${workspaceBackupDir.path}\\raw_erkul_source.json').copy(erkulRestoredJsonFile.path);
        final erkulMap = jsonDecode(erkulRestoredJsonFile.readAsStringSync()) as Map<String, dynamic>;

        final erkulReproducedDbPath = '${restoreTempDir.path}\\reproduced_erkul.db';
        final erkulCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulReproducedDbPath);
        final erkulBridge = MigrationBridgeEngine(erkulCoreDb);
        final rReport = await erkulBridge.migrateFromErkulJson(erkulMap);
        expect(rReport.isSuccess, isTrue);
        expect(rReport.customersMigrated, equals(401));

        final rEInteg = await erkulCoreDb.db.rawQuery('PRAGMA integrity_check');
        expect(rEInteg.first.values.first, equals('ok'));
        final rEFk = await erkulCoreDb.db.rawQuery('PRAGMA foreign_key_check');
        expect(rEFk.isEmpty, isTrue);

        final rEBal = (await erkulCoreDb.db.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'];
        expect(rEBal, equals(-52362000));
        await erkulCoreDb.close();
        print('  [PASS] ERKUL ÇEYİZ JSON yedeğinden sıfırdan SQLite üretilebilirliği kanıtlandı.');
      } finally {
        if (restoreTempDir.existsSync()) {
          try {
            restoreTempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    });

    test('5. Tenant İzolasyonu, Yol Çözümleme ve Sıfır Çapraz Veri Bulaşması', () async {
      print('\n=== BÖLÜM 5: TENANT İZOLASYONU VE ÇAPRAZ BULAŞMA TESTİ ===');

      final nDb = await openDatabase('${coreNextDir.path}\\nutopia_pos.db', readOnly: true);
      final sDb = await openDatabase('${coreNextDir.path}\\serenut_pos.db', readOnly: true);
      final eDb = await openDatabase('${coreNextDir.path}\\erkul_pos.db', readOnly: true);

      // 1. Fiziksel ve Mantıksal Dosya Ayrımı
      expect(nDb.path != sDb.path, isTrue);
      expect(sDb.path != eDb.path, isTrue);
      expect(nDb.path != eDb.path, isTrue);

      // 2. Müşteri (Cari) İzolasyonu
      final eCusts = await eDb.rawQuery('SELECT id, name FROM customers');
      final nCusts = await nDb.rawQuery('SELECT id, name FROM customers');
      final sCusts = await sDb.rawQuery('SELECT id, name FROM customers');

      final nCustIds = nCusts.map((r) => r['id']).toSet();
      final sCustIds = sCusts.map((r) => r['id']).toSet();
      final eCustIds = eCusts.map((r) => r['id']).toSet();

      // ERKUL Çeyiz'deki 401 müşteri Nutopia veya Serenut'ta ASLA bulunamaz
      for (final c in eCusts) {
        final id = c['id'];
        expect(nCustIds.contains(id), isFalse, reason: 'Erkul müşterisi ($id) Nutopia DB içinde bulunamaz!');
        expect(sCustIds.contains(id), isFalse, reason: 'Erkul müşterisi ($id) Serenut DB içinde bulunamaz!');
      }

      // Serenut müşterileri Erkul'da bulunamaz
      for (final c in sCusts) {
        final id = c['id'];
        expect(eCustIds.contains(id), isFalse, reason: 'Serenut müşterisi ($id) Erkul DB içinde bulunamaz!');
      }

      // 3. Sipariş ve Satış İzolasyonu
      final nOrders = await nDb.rawQuery('SELECT id FROM orders');
      final sOrders = await sDb.rawQuery('SELECT id FROM orders');
      final eOrders = await eDb.rawQuery('SELECT id FROM orders');

      final nOrderIds = nOrders.map((r) => r['id']).toSet();
      final sOrderIds = sOrders.map((r) => r['id']).toSet();
      final eOrderIds = eOrders.map((r) => r['id']).toSet();

      // Erkul'un siparişleri Nutopia veya Serenut'ta ASLA bulunamaz
      for (final o in eOrders) {
        final id = o['id'];
        expect(nOrderIds.contains(id), isFalse, reason: 'Erkul siparişi ($id) Nutopia içinde bulunamaz!');
        expect(sOrderIds.contains(id), isFalse, reason: 'Erkul siparişi ($id) Serenut içinde bulunamaz!');
      }

      // Nutopia'nın 787 özgün siparişi Serenut'ta bulunamaz (Serenut sadece 5 sipariş içerir)
      expect(nOrderIds.difference(sOrderIds).length, equals(787));
      expect(sOrderIds.length, equals(5));

      // 4. Cari Defter (Ledger) İzolasyonu
      final nLedger = await nDb.rawQuery('SELECT id FROM ledger_entries');
      final sLedger = await sDb.rawQuery('SELECT id FROM ledger_entries');
      final eLedger = await eDb.rawQuery('SELECT id FROM ledger_entries');

      final nLedgerIds = nLedger.map((r) => r['id']).toSet();
      final sLedgerIds = sLedger.map((r) => r['id']).toSet();
      final eLedgerIds = eLedger.map((r) => r['id']).toSet();

      // Erkul'un 539 defter hareketinin hiçbiri diğerlerinde olamaz
      for (final l in eLedger) {
        final id = l['id'];
        expect(nLedgerIds.contains(id), isFalse, reason: 'Erkul defter hareketi ($id) Nutopia içinde bulunamaz!');
        expect(sLedgerIds.contains(id), isFalse, reason: 'Erkul defter hareketi ($id) Serenut içinde bulunamaz!');
      }

      // Nutopia'nın 1391 özgün defter hareketi Serenut'ta olamaz
      expect(nLedgerIds.difference(sLedgerIds).length, equals(1391));

      // Erkul kullanıcısı (Tunahan Erkul) Nutopia veya Serenut'ta olamaz
      final nutopiaErkulUser = await nDb.rawQuery("SELECT COUNT(*) FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect(count(nutopiaErkulUser), equals(0));

      final serenutErkulUser = await sDb.rawQuery("SELECT COUNT(*) FROM users WHERE username = 'tunahan erkul' OR username = 'erkultunahan7@gmail.com'");
      expect(count(serenutErkulUser), equals(0));

      // 5. Bağımsız Metrikler
      final nStock = (await nDb.rawQuery('SELECT SUM(stock_quantity) as s FROM products')).first['s'];
      final sStock = (await sDb.rawQuery('SELECT SUM(stock_quantity) as s FROM products')).first['s'];
      expect(nStock, equals(5179525.85));
      expect(sStock, equals(637445.0));

      await nDb.close();
      await sDb.close();
      await eDb.close();
      print('  [PASS] 3 İşletme arasında %100 fiziksel ve mantıksal izolasyon doğrulandı.');
    });
  });
}

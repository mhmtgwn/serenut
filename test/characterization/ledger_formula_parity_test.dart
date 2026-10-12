// Faz 0 — Karakterizasyon testi: Müşteri bakiyesi formül paritesi.
//
// Amaç: Aynı finansal defter için bakiyeyi üreten / denetleyen BÜTÜN üretim
// yollarının bugün ne döndürdüğünü dondurmak. Bu test davranışı DEĞİŞTİRMEZ;
// yalnızca kaydeder. Faz 2'de (tek defter kuralı) beklenen değerler tek bir
// doğruya yakınsatılacak ve `knownDivergence` işaretleri kaldırılacaktır.
//
// Ölçülen yollar (hepsi production kodu, test içinde SQL kopyası yok):
//   trigger    : trg_ft_insert ile güncellenen customers.balance
//   details    : getTotalPaid - getTotalDebt (müşteri detay ekranı)
//   health     : checkHealth().customerBalanceDriftsCount (sağlık kontrolü)
//   reconciled : DB yeniden açıldığında _reconcileAllCustomerBalances sonucu
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_database_health_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';

class _Tx {
  final String type;
  final double amount;
  final double paid;
  final double debt;
  final bool softDelete;
  const _Tx(this.type, this.amount, this.paid, this.debt,
      {this.softDelete = false});
}

class _Observed {
  final double trigger;
  final double details;
  final int healthDrift;
  final double reconciled;
  const _Observed(this.trigger, this.details, this.healthDrift, this.reconciled);

  @override
  String toString() => 'trigger=$trigger details=$details '
      'healthDrift=$healthDrift reconciled=$reconciled';
}

const _custId = 'cust-parity';

Future<_Observed> _observe(String dbPath, List<_Tx> ledger) async {
  for (final suffix in ['', '-wal', '-shm']) {
    final f = File('$dbPath$suffix');
    if (await f.exists()) await f.delete();
  }
  DatabaseManager.overrideDatabasePath = dbPath;
  await DatabaseManager().close();

  var db = await DatabaseManager().getDatabase();
  var gateway = DbGatewayImpl.raw(db);
  var customers = SqliteCustomerRepository(gateway);
  final transactions = SqliteFinancialTransactionRepository(gateway);

  await customers.create(CustomerEntity(
    id: _custId,
    name: 'PARITY',
    email: 'parity@test.local',
    phone: '5550000000',
    balance: 0.0,
    createdAt: DateTime.utc(2026, 1, 1),
  ));

  var i = 0;
  for (final tx in ledger) {
    final id = 'tx-parity-${i++}';
    await transactions.create(FinancialTransactionEntity(
      id: id,
      type: tx.type,
      customerId: _custId,
      amount: tx.amount,
      paidAmount: tx.paid,
      debtAmount: tx.debt,
      date: DateTime.utc(2026, 1, 1, 12, i),
      referenceId: 'ref-$id',
    ));
    if (tx.softDelete) {
      // Production soft-delete yolu: yalnızca is_deleted işaretlenir.
      await db.rawUpdate(
          'UPDATE financial_transactions SET is_deleted = 1 WHERE id = ?',
          [id]);
    }
  }

  final trigger = await customers.getBalance(_custId);
  final details = await customers.getTotalPaid(_custId) -
      await customers.getTotalDebt(_custId);
  final health = await SqliteDatabaseHealthRepository(gateway).checkHealth();

  // Yeniden aç: startup reconcile production yolunu çalıştırır.
  await DatabaseManager().close();
  db = await DatabaseManager().getDatabase();
  gateway = DbGatewayImpl.raw(db);
  customers = SqliteCustomerRepository(gateway);
  final reconciled = await customers.getBalance(_custId);

  await DatabaseManager().close();
  return _Observed(
    _round(trigger),
    _round(details),
    health.customerBalanceDriftsCount,
    _round(reconciled),
  );
}

double _round(double v) => (v * 100).roundToDouble() / 100;

class _Scenario {
  final String name;
  final List<_Tx> ledger;
  final _Observed expected;

  const _Scenario(this.name, this.ledger, this.expected);
}

// GOLDEN değerler: Faz 2 Tek Defter Kuralı ile tüm yollar %100 eşitlendi.
// Tüm senaryolarda trigger == details == reconciled ve healthDrift == 0.
const _scenarios = <_Scenario>[
  _Scenario('S1 veresiye satış', [_Tx('sale', 100, 0, 100)],
      _Observed(-100, -100, 0, -100)),
  _Scenario('S2 kısmi ödemeli satış (debt_amount yazılmamış)',
      [_Tx('sale', 100, 30, 0)], _Observed(-70, -70, 0, -70)),
  _Scenario('S3 manual_debt (debt_amount yazılmamış)',
      [_Tx('manual_debt', 100, 0, 0)], _Observed(-100, -100, 0, -100)),
  _Scenario('S4 veresiye satış + iptal (iptal debt_amount=0)',
      [_Tx('sale', 100, 0, 100), _Tx('cancellation', 100, 0, 0)],
      _Observed(0, 0, 0, 0)),
  _Scenario('S5 peşin satış + peşin iade',
      [_Tx('sale', 100, 100, 0), _Tx('refund', 50, 50, 0)],
      _Observed(0, 0, 0, 0)),
  _Scenario('S6 veresiye satış + açık hesaba iade',
      [_Tx('sale', 100, 0, 100), _Tx('refund', 40, 0, 0)],
      _Observed(-60, -60, 0, -60)),
  _Scenario('S7 veresiye satış soft-delete edilmiş',
      [_Tx('sale', 100, 0, 100, softDelete: true)],
      _Observed(0, 0, 0, 0)),
  _Scenario('S8 veresiye + tahsilat (payment)',
      [_Tx('sale', 100, 0, 100), _Tx('payment', 60, 60, 0)],
      _Observed(-40, -40, 0, -40)),
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  final discovery = Platform.environment['PARITY_DISCOVERY'] == '1';
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('ledger_parity_');
  });

  tearDownAll(() async {
    DatabaseManager.overrideDatabasePath = null;
    await DatabaseManager().close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('Faz 0 — bakiye formül paritesi (karakterizasyon)', () {
    for (var n = 0; n < _scenarios.length; n++) {
      final s = _scenarios[n];
      test(s.name, () async {
        final observed =
            await _observe(p.join(tmp.path, 'parity_$n.db'), s.ledger);
        if (discovery) {
          // ignore: avoid_print
          print('PARITY | ${s.name} | $observed');
          return;
        }
        expect(observed.trigger, s.expected.trigger, reason: 'trigger');
        expect(observed.details, s.expected.details, reason: 'details');
        expect(observed.healthDrift, s.expected.healthDrift,
            reason: 'health');
        expect(observed.reconciled, s.expected.reconciled,
            reason: 'reconciled');
      });
    }
  });
}

// test/core_next/stage10_12_76_tenant_identity_resolver_test.dart
// STAGE 10.12.76: Tenant Identity Resolver and Fail-Closed Cutover Gate Verification
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/tenant_identity_resolver.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const targetPath = 'backups/nutopia_live_20261021_2055/nutopia_core_next_live.db';

  group('STAGE 10.12.76: TenantIdentityResolver Doğrulaması', () {
    test('1. Nutopia Cloud Merchant ID <-> Slug Eşleşmesi', () {
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1785241628448-c7f5677d',
          dbTenantId: 'nutopia',
        ),
        isTrue,
      );
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'nutopia',
          dbTenantId: 'nutopia',
        ),
        isTrue,
      );
    });

    test('2. Erkul ve Serenut Cloud Merchant ID <-> Slug Eşleşmesi', () {
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1791194455402-bdc6d8d1',
          dbTenantId: 'erkul',
        ),
        isTrue,
      );
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1785238670379-52219714',
          dbTenantId: 'serenut',
        ),
        isTrue,
      );
    });

    test('3. Çapraz Kiracı Reddi (Cross-Tenant Fail-Closed)', () {
      // Erkul lisanlı kullanıcı Nutopia DB'sine bağlanamaz
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1791194455402-bdc6d8d1',
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );
      // Nutopia lisanlı kullanıcı Erkul DB'sine bağlanamaz
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'comp-1785241628448-c7f5677d',
          dbTenantId: 'erkul',
        ),
        isFalse,
      );
    });

    test('4. Tanınmayan / Bilinmeyen / Boş Kiracı Reddi (Fail-Closed)', () {
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: 'hacker_tenant_999',
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: null,
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );
      expect(
        TenantIdentityResolver.matches(
          requestedTenantId: '',
          dbTenantId: 'nutopia',
        ),
        isFalse,
      );
    });
  });

  group('STAGE 10.12.76: PilotCutoverGate Tenant Doğrulaması', () {
    test('5. PilotCutoverGate Nutopia Cloud Merchant ID ile Başarıyla Eşleşir', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      const gate = PilotCutoverGate(
        overrideGenerator: _mockOverrideGenerator,
      );

      const legacyPath = 'backups/nutopia_live_20261021_2055/nutopia_live_backup.db';

      final result = await gate.evaluate(
        prefs: prefs,
        legacyDbPath: File(legacyPath).absolute.path,
        targetDbPath: File(targetPath).absolute.path,
        requestedTenantId: 'comp-1785241628448-c7f5677d', // Nutopia cloud merchant ID
      );

      print('GATE EVAL WITH NUTOPIA MERCHANT ID: ${result.status} | Reason: ${result.reason}');
      expect(result.status, equals(PilotGateStatus.pilotActiveApproved));
      expect(result.isPilotActive, isTrue);
    });

    test('6. PilotCutoverGate Yanlış Tenant ID Geldiğinde Kesinlikle Bloke Eder', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        PilotCutoverGate.prefKeyKillSwitch: false,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        'last_backup_date': DateTime.now().toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();

      const gate = PilotCutoverGate(
        overrideGenerator: _mockOverrideGenerator,
      );

      const legacyPath = 'backups/nutopia_live_20261021_2055/nutopia_live_backup.db';

      final result = await gate.evaluate(
        prefs: prefs,
        legacyDbPath: File(legacyPath).absolute.path,
        targetDbPath: File(targetPath).absolute.path,
        requestedTenantId: 'comp-1791194455402-bdc6d8d1', // Erkul ID'si Nutopia DB'sine verilirse
      );

      print('GATE EVAL WITH WRONG TENANT: ${result.status} | Reason: ${result.reason}');
      expect(result.status, equals(PilotGateStatus.blockedTenantMismatch));
      expect(result.isPilotActive, isFalse);
    });
  });
}

final _dummyProvider = Provider<int>((ref) => 1);

Future<List<Override>?> _mockOverrideGenerator({
  required String requestedTenantId,
  required String legacyDbPath,
  required String targetDbPath,
  required bool enableSalesEngine,
  DatabaseFactory? dbFactory,
}) async {
  return [_dummyProvider.overrideWithValue(1)];
}

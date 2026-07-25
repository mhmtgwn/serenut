// test/unit/update_v2/manifest_contract_test.dart
// Serenut Platform — Client Release Manifest Contract Verification Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/update_v2/release_manifest.dart';
import 'package:serenutos/domain/models/update_v2/bootstrapper_manifest.dart';
import 'package:serenutos/domain/models/update_v2/update_telemetry_event.dart';
import 'package:serenutos/infrastructure/services/crypto/rsa_sha256_signature_verifier.dart';

void main() {
  group('ReleaseManifest Contract Tests', () {
    final validJson = {
      'schemaVersion': 1,
      'manifestVersion': '1.0',
      'releaseId': 'rel-2026.07.25.4',
      'version': '1.2.0+22',
      'channel': 'stable',
      'publishedAt': '2026-07-25T18:20:00Z',
      'buildMetadata': {
        'commitHash': 'abc1234f567890',
        'buildNumber': 22,
        'buildDate': '2026-07-25T18:00:00Z',
        'signatureAlgorithm': 'RSA-SHA256'
      },
      'compatibility': {
        'minClientVersion': '1.0.0+1',
        'minimumUpdaterVersion': '1.0.0',
        'requiredBootstrapper': '1',
        'requiredPreVersion': '1.1.0+0',
        'migrationRequired': true,
        'targetSchemaVersion': 4
      },
      'rules': {
        'isMandatory': false,
        'allowRollback': true,
        'minFreeDiskMb': 300,
        'minRamMb': 2048,
        'supportedArchitectures': ['x64']
      },
      'artifacts': [
        {
          'type': 'installer_windows',
          'filename': 'SerenutOSSetup-1.2.0.exe',
          'downloadUrl': '/api/v1/releases/artifacts/SerenutOSSetup-1.2.0.exe',
          'sizeBytes': 48120890,
          'sha256': '4dd4c7b462651ee66f2529bb561a5b17417d32095220cf1908ad94362407503c',
          'signature': 'MEUCIQDx7...RSA256_BASE64_SIG...'
        }
      ]
    };

    test('Valid release_manifest.json parses successfully', () {
      final manifest = ReleaseManifest.fromJson(validJson);
      expect(manifest.schemaVersion, equals(1));
      expect(manifest.releaseId, equals('rel-2026.07.25.4'));
      expect(manifest.version, equals('1.2.0+22'));
      expect(manifest.channel, equals('stable'));
      expect(manifest.artifacts.length, equals(1));
      expect(
        manifest.artifacts.first.sha256,
        equals('4dd4c7b462651ee66f2529bb561a5b17417d32095220cf1908ad94362407503c'),
      );
    });

    test('Rejects unsupported future schemaVersion (e.g. 99)', () {
      final invalidJson = Map<String, dynamic>.from(validJson);
      invalidJson['schemaVersion'] = 99;

      expect(
        () => ReleaseManifest.fromJson(invalidJson),
        throwsA(isA<UnsupportedSchemaException>()),
      );
    });

    test('Rejects missing artifacts list', () {
      final invalidJson = Map<String, dynamic>.from(validJson);
      invalidJson['artifacts'] = [];

      expect(
        () => ReleaseManifest.fromJson(invalidJson),
        throwsA(isA<InvalidManifestException>()),
      );
    });

    test('Rejects invalid SHA-256 string format', () {
      final invalidJson = Map<String, dynamic>.from(validJson);
      invalidJson['artifacts'] = [
        {
          'type': 'installer_windows',
          'filename': 'SerenutOSSetup-1.2.0.exe',
          'downloadUrl': '/api/v1/releases/artifacts/SerenutOSSetup-1.2.0.exe',
          'sizeBytes': 48120890,
          'sha256': 'invalid-not-64-hex-chars',
          'signature': 'SIG'
        }
      ];

      expect(
        () => ReleaseManifest.fromJson(invalidJson),
        throwsA(isA<InvalidManifestException>()),
      );
    });
  });

  group('BootstrapperManifest Contract Tests', () {
    final validBootstrapperJson = {
      'schemaVersion': 1,
      'correlationId': 'upd-92a1-4f81',
      'appPid': 14208,
      'targetVersion': '1.2.0+22',
      'installerPath': 'C:\\Users\\Temp\\installer.exe',
      'targetDir': 'C:\\Users\\AppData\\SerenutOS',
      'backupDir': 'C:\\Users\\AppData\\SerenutOS\\update_backups',
      'postLaunchExe': 'serenutos.exe'
    };

    test('Valid bootstrapper_manifest.json parses successfully', () {
      final bm = BootstrapperManifest.fromJson(validBootstrapperJson);
      expect(bm.schemaVersion, equals(1));
      expect(bm.correlationId, equals('upd-92a1-4f81'));
      expect(bm.appPid, equals(14208));
    });
  });

  group('UpdateTelemetryEvent Contract Tests', () {
    final validTelemetryJson = {
      'schemaVersion': 1,
      'correlationId': 'upd-92a1-4f81',
      'deviceId': 'dev-win-001',
      'fromVersion': '1.1.9+21',
      'toVersion': '1.2.0+22',
      'eventType': 'INSTALL_SUCCESS',
      'timestamp': '2026-07-25T18:22:10Z'
    };

    test('Valid UpdateTelemetryEvent parses successfully', () {
      final event = UpdateTelemetryEvent.fromJson(validTelemetryJson);
      expect(event.schemaVersion, equals(1));
      expect(event.eventType, equals(UpdateEventType.installSuccess));
      expect(event.eventType.toSchemaString(), equals('INSTALL_SUCCESS'));
    });
  });

  group('SignatureVerifier Contract Tests', () {
    test('Rejects empty signature on verifyManifest', () async {
      final verifier = RsaSha256SignatureVerifier();
      final result = await verifier.verifyManifest(
        manifestContent: '{"test":true}',
        signature: '',
      );
      expect(result, isFalse);
    });

    test('Rejects unconfigured public key on verifyManifest', () async {
      final verifier = RsaSha256SignatureVerifier(defaultModulus: '');
      final result = await verifier.verifyManifest(
        manifestContent: '{"test":true}',
        signature: 'c29tZXNpZ25hdHVyZQ==',
      );
      expect(result, isFalse);
    });
  });
}

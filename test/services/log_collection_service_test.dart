import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/services/log_collection_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/config/environment.dart';
import 'package:pointycastle/export.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TelemetryService telemetryService;
  late LogCollectionService logCollectionService;
  late ApiClient mockApiClient;
  bool uploadCalled = false;
  String? uploadedBase64;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('log_collection_test');
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    telemetryService = TelemetryService();
    mockApiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
    
    mockApiClient.mockHandler = (request) {
      if (request.url.path.contains('/api/v1/logs/upload')) {
        uploadCalled = true;
        if (request is http.Request) {
          uploadedBase64 = jsonDecode(request.body)['encrypted_data'];
        }
        return const ApiResponse(statusCode: 200, body: '{"success":true}', headers: {});
      }
      return const ApiResponse(statusCode: 404, body: '{}', headers: {});
    };

    logCollectionService = LogCollectionService(mockApiClient);
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await telemetryService.clearLogs();
    uploadCalled = false;
    uploadedBase64 = null;
  });

  group('LogCollectionService Integration Tests', () {
    test('Collects telemetry logs, encrypts them, and uploads via API', () async {
      // 1. Write some telemetry logs
      await telemetryService.logEvent('diagnostic_event_1', {'status': 'ok'});
      await telemetryService.logEvent('diagnostic_event_2', {'error': 'none'});

      // Ensure the log file is created in tempDir/telemetry
      final telemetryDir = Directory('${tempDir.path}/telemetry');
      expect(telemetryDir.existsSync(), isTrue);
      
      final files = telemetryDir.listSync().whereType<File>().toList();
      expect(files, isNotEmpty);

      // 2. Call zipAndUploadLogs
      final success = await logCollectionService.zipAndUploadLogs(deviceId: 'test_dev_123');
      
      // 3. Verify upload success
      expect(success, isTrue);
      expect(uploadCalled, isTrue);
      expect(uploadedBase64, isNotNull);

      // 4. Verify encrypted data can be decrypted using the same key and IV
      final encryptedBytes = base64Decode(uploadedBase64!);
      
      final keyBytes = utf8.encode('default_log_sec_key_128b_!!_12345'.padRight(32, '0'));
      final ivBytes = utf8.encode('default_log_iv!!'.padRight(16, '0'));
      
      final keyParam = KeyParameter(Uint8List.fromList(keyBytes.sublist(0, 16)));
      final params = ParametersWithIV(keyParam, Uint8List.fromList(ivBytes.sublist(0, 16)));
      
      final cipher = CBCBlockCipher(AESEngine());
      cipher.init(false, params); // false for decryption
      
      final decryptedBytes = Uint8List(encryptedBytes.length);
      int offset = 0;
      while (offset < encryptedBytes.length) {
        cipher.processBlock(Uint8List.fromList(encryptedBytes), offset, decryptedBytes, offset);
        offset += 16;
      }
      
      // Remove PKCS7 padding
      final padLength = decryptedBytes.last;
      final unpadded = decryptedBytes.sublist(0, decryptedBytes.length - padLength);
      
      final decryptedText = utf8.decode(unpadded);
      
      // 5. Verify the logs are inside the decrypted payload
      expect(decryptedText, contains('=== DEVICE DIAGNOSTIC LOGS : test_dev_123 ==='));
      expect(decryptedText, contains('diagnostic_event_1'));
      expect(decryptedText, contains('diagnostic_event_2'));
    });
  });
}

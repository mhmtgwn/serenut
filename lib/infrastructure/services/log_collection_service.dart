// lib/infrastructure/services/log_collection_service.dart
// Serenut OS — Remote Encrypted Log Collection (Sprint 10)

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class LogCollectionService {
  final ApiClient _apiClient;

  LogCollectionService(this._apiClient);

  /// Zips, encrypts, and uploads local logs to SaaS platform
  Future<bool> zipAndUploadLogs({required String deviceId}) async {
    try {
      final appDocsDir = await getApplicationDocumentsDirectory();
      
      // Look for telemetry logs
      final logDir = Directory('${appDocsDir.path}/telemetry');
      final logFiles = <File>[];
      if (logDir.existsSync()) {
        logFiles.addAll(logDir.listSync().whereType<File>());
      }

      // Gather text content of logs
      final StringBuffer logsAggregate = StringBuffer();
      logsAggregate.writeln('=== DEVICE DIAGNOSTIC LOGS : $deviceId ===');
      if (logFiles.isEmpty) {
        logsAggregate.writeln('No local log files found on device support storage.');
      } else {
        for (final file in logFiles) {
          logsAggregate.writeln('--- FILE: ${file.path.split("/").last} ---');
          logsAggregate.writeln(await file.readAsString());
        }
      }

      // Cryptographic encryption payload using simple AES block cipher via PointyCastle
      final rawData = utf8.encode(logsAggregate.toString());
      final encryptedBytes = _encryptAes(rawData);

      // Upload as base64 envelope
      final base64Payload = base64Encode(encryptedBytes);
      final response = await _apiClient.post(
        '/api/v1/logs/upload?device_id=$deviceId',
        {'encrypted_data': base64Payload},
      );

      if (response.statusCode == 200) {
        debugPrint('[LogCollection] Diagnostic logs successfully pushed to SaaS.');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[LogCollection] Failed to package and upload logs: $e');
      return false;
    }
  }

  /// Encrypt helper using AES-CBC via PointyCastle
  List<int> _encryptAes(List<int> plainText) {
    // 128-bit key derived from shared secret
    final keyBytes = utf8.encode('serenut_log_sec_key_128b_!!'); // 32 bytes key
    final ivBytes = utf8.encode('serenut_log_iv!!'); // 16 bytes IV

    final keyParam = KeyParameter(Uint8List.fromList(keyBytes.sublist(0, 16)));
    final params = ParametersWithIV(keyParam, Uint8List.fromList(ivBytes.sublist(0, 16)));

    final cipher = CBCBlockCipher(AESEngine());
    cipher.init(true, params);

    // Apply PKCS7 Padding
    final paddedText = _padPKCS7(plainText, 16);
    final Uint8List out = Uint8List(paddedText.length);

    int offset = 0;
    while (offset < paddedText.length) {
      cipher.processBlock(Uint8List.fromList(paddedText), offset, out, offset);
      offset += 16;
    }

    return out.toList();
  }

  List<int> _padPKCS7(List<int> source, int blockSize) {
    final int padLength = blockSize - (source.length % blockSize);
    final List<int> padded = List<int>.from(source);
    for (int i = 0; i < padLength; i++) {
      padded.add(padLength);
    }
    return padded;
  }
}

// lib/domain/models/update_v2/journal_record.dart
// Serenut Platform — Client NDJSON Journal Record

import 'dart:convert';
import 'package:crypto/crypto.dart';

class JournalRecord {
  final int schemaVersion;
  final String timestamp;
  final String correlationId;
  final int sequenceNumber;
  final String eventType;
  final String state;
  final Map<String, dynamic> payload;
  final String checksum;

  JournalRecord({
    required this.schemaVersion,
    required this.timestamp,
    required this.correlationId,
    required this.sequenceNumber,
    required this.eventType,
    required this.state,
    required this.payload,
    required this.checksum,
  });

  /// Computes a SHA-256 checksum of the record fields for line integrity.
  static String calculateChecksum({
    required int schemaVersion,
    required String timestamp,
    required String correlationId,
    required int sequenceNumber,
    required String eventType,
    required String state,
    required Map<String, dynamic> payload,
  }) {
    final payloadStr = jsonEncode(payload);
    final data = [
      schemaVersion,
      timestamp,
      correlationId,
      sequenceNumber,
      eventType,
      state,
      payloadStr
    ].join('|');
    return sha256.convert(utf8.encode(data)).toString();
  }

  factory JournalRecord.create({
    required String correlationId,
    required int sequenceNumber,
    required String eventType,
    required String state,
    required Map<String, dynamic> payload,
    int schemaVersion = 1,
  }) {
    final ts = DateTime.now().toIso8601String();
    final sum = calculateChecksum(
      schemaVersion: schemaVersion,
      timestamp: ts,
      correlationId: correlationId,
      sequenceNumber: sequenceNumber,
      eventType: eventType,
      state: state,
      payload: payload,
    );
    return JournalRecord(
      schemaVersion: schemaVersion,
      timestamp: ts,
      correlationId: correlationId,
      sequenceNumber: sequenceNumber,
      eventType: eventType,
      state: state,
      payload: payload,
      checksum: sum,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'timestamp': timestamp,
      'correlationId': correlationId,
      'sequenceNumber': sequenceNumber,
      'eventType': eventType,
      'state': state,
      'payload': payload,
      'checksum': checksum,
    };
  }

  factory JournalRecord.fromJson(Map<String, dynamic> json) {
    return JournalRecord(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      timestamp: json['timestamp'] as String? ?? '',
      correlationId: json['correlationId'] as String? ?? '',
      sequenceNumber: json['sequenceNumber'] as int? ?? 0,
      eventType: json['eventType'] as String? ?? '',
      state: json['state'] as String? ?? '',
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      checksum: json['checksum'] as String? ?? '',
    );
  }

  /// Verifies if the checksum matches the fields of this record.
  bool verify() {
    final computed = calculateChecksum(
      schemaVersion: schemaVersion,
      timestamp: timestamp,
      correlationId: correlationId,
      sequenceNumber: sequenceNumber,
      eventType: eventType,
      state: state,
      payload: payload,
    );
    return computed == checksum;
  }
}

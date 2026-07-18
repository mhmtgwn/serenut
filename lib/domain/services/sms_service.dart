// lib/domain/services/sms_service.dart
// Serenut OS — SMS Notification Service
// Supports: Netgsm (TR), Twilio (global)
// Features: Queue, retry, offline buffering, delivery status logging
// Created: 24 Jun 2026

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

// ── SMS Provider Enum ─────────────────────────────────────────────────────────
enum SmsProvider { sim, netgsm, twilio, custom, none }

// ── SMS Queue Item ─────────────────────────────────────────────────────────────
class SmsQueueItem {
  final String id;
  final String phone;
  final String message;
  final DateTime createdAt;
  int retryCount;
  String status; // 'pending' | 'sent' | 'failed'

  SmsQueueItem({
    required this.id,
    required this.phone,
    required this.message,
    required this.createdAt,
    this.retryCount = 0,
    this.status = 'pending',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone': phone,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'status': status,
      };

  factory SmsQueueItem.fromMap(Map<String, dynamic> map) => SmsQueueItem(
        id: map['id'] as String,
        phone: map['phone'] as String,
        message: map['message'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        retryCount: (map['retryCount'] as int?) ?? 0,
        status: (map['status'] as String?) ?? 'pending',
      );
}

// ── SMS Configuration ─────────────────────────────────────────────────────────
class SmsConfig {
  final SmsProvider provider;
  final String apiKey;
  final String username; // Netgsm: kullanıcı adı | Twilio: accountSid
  final String sender; // Netgsm: başlık | Twilio: phone number
  final String? apiSecret; // Twilio only

  // SIM Specifics
  final int? simSubscriptionId;
  final int? monthlyLimit;
  final int sentThisMonth;
  final int? limitResetMonth;

  const SmsConfig({
    required this.provider,
    required this.apiKey,
    required this.username,
    required this.sender,
    this.apiSecret,
    this.simSubscriptionId,
    this.monthlyLimit,
    this.sentThisMonth = 0,
    this.limitResetMonth,
  });
}

// ── SMS Service ───────────────────────────────────────────────────────────────
class SmsService {
  static const String _queueKey = 'serenut_sms_queue';
  static const String _logKey = 'serenut_sms_log';
  static const int _maxRetries = 3;
  static const int _maxLogItems = 200;

  final SmsConfig? _config;
  final http.Client _httpClient;
  final Future<void> Function()? onSmsSent;
  final Future<void> Function(String phone, String message, String status,
      String? errorMessage, String messageId)? onSmsDispatched;
  bool _isSending = false;

  SmsService({
    SmsConfig? config,
    http.Client? httpClient,
    this.onSmsSent,
    this.onSmsDispatched,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Request permissions required for local SIM SMS sending (SMS & Phone state/numbers)
  Future<bool> requestSimPermissions() async {
    final statusSms = await Permission.sms.request();
    final statusPhone = await Permission.phone.request();
    return statusSms.isGranted && statusPhone.isGranted;
  }

  /// Check if permissions are already granted for SIM SMS sending
  Future<bool> hasSimPermissions() async {
    final statusSms = await Permission.sms.status;
    final statusPhone = await Permission.phone.status;
    return statusSms.isGranted && statusPhone.isGranted;
  }

  /// Send an SMS immediately. Falls back to queue if offline or fails.
  Future<bool> sendSms(String phone, String message) async {
    final config = _config;
    if (config == null || config.provider == SmsProvider.none) {
      return false; // SMS not configured
    }

    final item = SmsQueueItem(
      id: const Uuid().v4(),
      phone: _normalizePhone(phone),
      message: message,
      createdAt: DateTime.now(),
    );

    // Try to send immediately
    final success = await _dispatch(item, config);
    if (!success) {
      // Queue for later retry
      await _enqueue(item);
    }
    return success;
  }

  /// Sends a message claimed from the Serenut cloud queue through this
  /// device's local SIM. Cloud status is reported by the gateway worker, so
  /// the normal sync-local callback is intentionally suppressed.
  Future<bool> sendGatewaySms(String phone, String message) async {
    final config = _config;
    if (config == null || config.provider != SmsProvider.sim) return false;
    final item = SmsQueueItem(
      id: const Uuid().v4(),
      phone: _normalizePhone(phone),
      message: message,
      createdAt: DateTime.now(),
    );
    return _dispatch(item, config, reportDispatch: false);
  }

  /// Queue an SMS without sending (for offline scenarios).
  Future<void> queueSms(String phone, String message) async {
    final item = SmsQueueItem(
      id: const Uuid().v4(),
      phone: _normalizePhone(phone),
      message: message,
      createdAt: DateTime.now(),
    );
    await _enqueue(item);
  }

  /// Process all queued SMS messages. Call on app foreground / network restore.
  Future<int> processSmsQueue() async {
    final config = _config;
    if (config == null || config.provider == SmsProvider.none) return 0;
    if (_isSending) return 0;

    _isSending = true;
    var sentCount = 0;

    try {
      final queue = await _loadQueue();
      final pending = queue
          .where((i) => i.status == 'pending' && i.retryCount < _maxRetries)
          .toList();

      for (final item in pending) {
        final success = await _dispatch(item, config);
        if (success) {
          item.status = 'sent';
          sentCount++;
        } else {
          item.retryCount++;
          if (item.retryCount >= _maxRetries) {
            item.status = 'failed';
          }
        }
      }

      await _saveQueue(queue);
    } finally {
      _isSending = false;
    }

    return sentCount;
  }

  /// Get pending queue count.
  Future<int> getPendingCount() async {
    final queue = await _loadQueue();
    return queue.where((i) => i.status == 'pending').length;
  }

  /// Get SMS delivery log (last N items).
  Future<List<Map<String, dynamic>>> getDeliveryLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_logKey) ?? [];
    return raw.reversed
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();
  }

  /// Send sale completion SMS to customer.
  Future<void> sendSaleCompletionSms({
    required String phone,
    required String customerName,
    required double totalAmount,
    required double paidAmount,
    required String saleId,
    required String currency,
    String? businessName,
    String? template,
  }) async {
    if (phone.isEmpty) return;

    final debt = (totalAmount - paidAmount).clamp(0.0, double.maxFinite);
    final debtStr =
        debt > 0 ? ' Bakiye: $currency${debt.toStringAsFixed(2)}' : '';

    final message = template != null && template.isNotEmpty
        ? template
            .replaceAll('{musteri}', customerName)
            .replaceAll('{tutar}', '$currency${totalAmount.toStringAsFixed(2)}')
            .replaceAll('{odenen}', '$currency${paidAmount.toStringAsFixed(2)}')
            .replaceAll('{bakiye}', debtStr)
            .replaceAll('{firma}', businessName ?? 'Serenut OS')
        : '${businessName ?? 'Serenut OS'}: Sayın $customerName, '
            '$currency${totalAmount.toStringAsFixed(2)} tutarındaki alışverişiniz için teşekkürler.$debtStr';

    await queueSms(phone, message);
    // Process immediately (non-blocking)
    unawaited(processSmsQueue());
  }

  // ── Private — Provider Dispatch ────────────────────────────────────────────

  Future<bool> _dispatch(SmsQueueItem item, SmsConfig config,
      {bool reportDispatch = true}) async {
    if (config.provider == SmsProvider.sim &&
        config.monthlyLimit != null &&
        config.sentThisMonth >= config.monthlyLimit!) {
      await _logDelivery(item, success: false);
      if (reportDispatch) {
        unawaited(onSmsDispatched?.call(item.phone, item.message, 'failed',
                'Aylık SMS limiti aşıldı.', item.id) ??
            Future.value());
      }
      return false;
    }

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        bool success;
        switch (config.provider) {
          case SmsProvider.sim:
            success = await _sendSim(item.phone, item.message, config);
          case SmsProvider.netgsm:
            success = await _sendNetgsm(item.phone, item.message, config);
          case SmsProvider.twilio:
            success = await _sendTwilio(item.phone, item.message, config);
          case SmsProvider.custom:
            success = false;
          case SmsProvider.none:
            return false;
        }
        if (success) {
          await _logDelivery(item, success: true);
          if (reportDispatch) {
            unawaited(onSmsDispatched?.call(
                    item.phone, item.message, 'sent', null, item.id) ??
                Future.value());
          }
          return true;
        }
      } catch (_) {
        // retry
      }
      if (attempt < 3) {
        await Future.delayed(
            Duration(seconds: attempt * 2)); // Exponential backoff: 2s, 4s
      }
    }
    await _logDelivery(item, success: false);
    if (reportDispatch) {
      unawaited(onSmsDispatched?.call(item.phone, item.message, 'failed',
              'Operatör/Sağlayıcı hatası veya sinyal yok.', item.id) ??
          Future.value());
    }
    return false;
  }

  // ── Netgsm HTTP API ────────────────────────────────────────────────────────
  // Docs: https://www.netgsm.com.tr/dokuman/

  Future<bool> _sendNetgsm(
      String phone, String message, SmsConfig config) async {
    final url = Uri.parse('https://api.netgsm.com.tr/sms/send/get/');
    final params = {
      'usercode': config.username,
      'password': config.apiKey,
      'gsmno': phone.replaceAll('+', '').replaceAll(' ', ''),
      'message': message,
      'msgheader': config.sender,
      'encoding': 'TR',
    };

    final response = await _httpClient
        .get(Uri.parse('$url?${_buildQuery(params)}'))
        .timeout(const Duration(seconds: 15));

    // Netgsm returns a code: 00 = success, 20 = auth error, etc.
    final body = response.body.trim();
    return response.statusCode == 200 && body.startsWith('00');
  }

  // ── Twilio REST API ────────────────────────────────────────────────────────
  // Docs: https://www.twilio.com/docs/sms/api

  Future<bool> _sendTwilio(
      String phone, String message, SmsConfig config) async {
    if (config.apiSecret == null) return false;

    final url = Uri.parse(
      'https://api.twilio.com/2010-04-01/Accounts/${config.username}/Messages.json',
    );

    final credentials =
        base64.encode(utf8.encode('${config.username}:${config.apiSecret}'));

    final response = await _httpClient.post(
      url,
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'To': phone,
        'From': config.sender,
        'Body': message,
      },
    ).timeout(const Duration(seconds: 15));

    return response.statusCode == 201;
  }

  // ── Queue Persistence ──────────────────────────────────────────────────────

  Future<void> _enqueue(SmsQueueItem item) async {
    final queue = await _loadQueue();
    queue.add(item);
    await _saveQueue(queue);
  }

  Future<List<SmsQueueItem>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    return raw
        .map((e) => SmsQueueItem.fromMap(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveQueue(List<SmsQueueItem> queue) async {
    final prefs = await SharedPreferences.getInstance();
    // Keep only last 500 items to prevent unbounded growth
    final trimmed =
        queue.length > 500 ? queue.sublist(queue.length - 500) : queue;
    await prefs.setStringList(
      _queueKey,
      trimmed.map((e) => jsonEncode(e.toMap())).toList(),
    );
  }

  // ── Delivery Log ───────────────────────────────────────────────────────────

  Future<void> _logDelivery(SmsQueueItem item, {required bool success}) async {
    final prefs = await SharedPreferences.getInstance();
    final log = prefs.getStringList(_logKey) ?? [];
    log.add(jsonEncode({
      'id': item.id,
      'phone': item.phone,
      'success': success,
      'retries': item.retryCount,
      'timestamp': DateTime.now().toIso8601String(),
    }));
    // Rotate log
    if (log.length > _maxLogItems) {
      log.removeRange(0, log.length - _maxLogItems);
    }
    await prefs.setStringList(_logKey, log);
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  /// Normalize Turkish phone numbers to international format.
  String _normalizePhone(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('0')) p = '+90${p.substring(1)}';
    if (!p.startsWith('+')) p = '+90$p';
    return p;
  }

  String _buildQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');

  Future<bool> _sendSim(String phone, String message, SmsConfig config) async {
    try {
      final Map<String, dynamic> args = {
        'phone': phone,
        'message': message,
      };
      if (config.simSubscriptionId != null) {
        args['subscriptionId'] = config.simSubscriptionId;
      }
      final bool? result = await const MethodChannel('serenut/sms_sender')
          .invokeMethod<bool>('sendSmsViaSim', args);

      final success = result ?? false;
      if (success) {
        await onSmsSent?.call();
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

// ── Helper for fire-and-forget ────────────────────────────────────────────────
void unawaited(Future<dynamic> future) {
  future.ignore();
}

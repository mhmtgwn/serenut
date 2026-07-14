// lib/domain/notifications/template_resolver.dart
// Serenut POS — SMS Template Resolver
// Reads active template from Settings.smsTemplate JSON,
// resolves {variable} tokens, returns final message string.
// Created: 01 Jul 2026

import 'dart:convert';
import 'package:serenutos/domain/models/settings.dart';

// ── SMS Event Type Constants ──────────────────────────────────────────────────
// Template IDs stored in Settings.smsTemplate JSON.
// New format (preferred): 'sale_created', 'debt_created', etc.
// Legacy format (backward compat): 'sale', 'debt', etc.

const kSmsEventSaleCreated = 'sale_created';
const kSmsEventDebtCreated = 'debt_created';
const kSmsEventCollectionRecorded = 'collection_recorded';
const kSmsEventOrderCreated = 'order_created';
const kSmsEventOrderPreparing = 'order_preparing';
const kSmsEventOrderReady = 'order_ready';
const kSmsEventOrderDelivered = 'order_delivered';
const kSmsEventOrderCancelled = 'order_cancelled';
const kSmsEventDiscountApplied = 'discount_applied';

// Legacy aliases (still supported in template JSON)
const _kLegacySale = 'sale';
const _kLegacyDebt = 'debt';
const _kLegacyCollection = 'collection';
const _kLegacyOrder = 'order';

// Map new → legacy for backward compat lookup
const _legacyAliases = <String, String>{
  kSmsEventSaleCreated: _kLegacySale,
  kSmsEventDebtCreated: _kLegacyDebt,
  kSmsEventCollectionRecorded: _kLegacyCollection,
  kSmsEventOrderCreated: _kLegacyOrder,
};

// ── Template Variables Reference ──────────────────────────────────────────────
// {customer}  → müşteri adı
// {amount}    → toplam tutar
// {paid}      → ödenen tutar
// {debt}      → kalan borç
// {id}        → satış / tahsilat no
// {business}  → işletme adı
// {date}      → işlem tarihi (dd.MM.yyyy)
// {items}     → ürün listesi (opsiyonel)

// ── TemplateResolver ─────────────────────────────────────────────────────────
class TemplateResolver {
  const TemplateResolver();

  /// Resolve [eventType] template from [settings] with given [vars].
  ///
  /// Returns null if:
  /// - SMS is disabled globally (Settings.smsEnabled == false)
  /// - No template found for [eventType]
  /// - Template is disabled (enabled: false)
  String? resolve({
    required String eventType,
    required Settings settings,
    required Map<String, String> vars,
  }) {
    if (!settings.smsEnabled) return null;

    final templateStr = settings.smsTemplate;
    if (templateStr == null || templateStr.trim().isEmpty) return null;

    final templateText = _findTemplate(eventType, templateStr);
    if (templateText == null) return null;

    return _fillTokens(templateText, vars);
  }

  /// Check if [eventType] template exists and is enabled.
  bool isEnabled({required String eventType, required Settings settings}) {
    if (!settings.smsEnabled) return false;
    final t = settings.smsTemplate;
    if (t == null || t.trim().isEmpty) return false;
    return _findTemplate(eventType, t) != null;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  String? _findTemplate(String eventType, String templateJson) {
    try {
      final decoded = jsonDecode(templateJson);
      if (decoded is! List) return null;

      // Try new format ID first, then legacy alias
      final candidateIds = [
        eventType,
        _legacyAliases[eventType],
      ].whereType<String>().toList();

      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        final enabled = item['enabled'];
        final template = item['template']?.toString();

        if (id == null || template == null || template.trim().isEmpty) continue;
        if (enabled != true) continue;
        if (candidateIds.contains(id)) return template;
      }
    } catch (_) {
      // Malformed JSON — silent
    }
    return null;
  }

  String _fillTokens(String template, Map<String, String> vars) {
    var result = template;
    vars.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}

// ── Variable Map Builders ─────────────────────────────────────────────────────
// Convenience factory methods for each event type.

class SmsTemplateVars {
  SmsTemplateVars._();

  static Map<String, String> forSale({
    required String customerName,
    required double totalAmount,
    required double paidAmount,
    required String saleId,
    required String businessName,
    String currency = '₺',
    List<String>? itemNames,
  }) {
    return {
      'customer': customerName,
      'amount': _fmt(totalAmount, currency),
      'paid': _fmt(paidAmount, currency),
      'debt':
          _fmt((totalAmount - paidAmount).clamp(0, double.maxFinite), currency),
      'id': saleId,
      'business': businessName,
      'date': _today(),
      'items': itemNames?.join(', ') ?? '',
      'discount': _fmt(0, currency),
    };
  }

  static Map<String, String> forDebt({
    required String customerName,
    required double totalAmount,
    required double paidAmount,
    required String saleId,
    required String businessName,
    required double currentBalance,
    String currency = '₺',
  }) {
    final debtAmount = (totalAmount - paidAmount).clamp(0.0, double.maxFinite);
    final newBalance = currentBalance - debtAmount;
    return {
      'customer': customerName,
      'amount': _fmt(totalAmount, currency),
      'paid': _fmt(paidAmount, currency),
      'debt': _fmt(debtAmount, currency),
      'balance': _fmt(newBalance.abs(), currency),
      'id': saleId,
      'business': businessName,
      'date': _today(),
      'items': '',
      'discount': _fmt(0, currency),
    };
  }

  static Map<String, String> forCollection({
    required String customerName,
    required double collectedAmount,
    required double remainingDebt,
    required String transactionId,
    required String businessName,
    String currency = '₺',
  }) {
    return {
      'customer': customerName,
      'amount': _fmt(collectedAmount, currency),
      'paid': _fmt(collectedAmount, currency),
      'debt':
          remainingDebt > 0 ? _fmt(remainingDebt, currency) : '0,00 $currency',
      'balance':
          remainingDebt > 0 ? _fmt(remainingDebt, currency) : '0,00 $currency',
      'id': transactionId,
      'business': businessName,
      'date': _today(),
      'items': '',
      'discount': _fmt(0, currency),
    };
  }

  static Map<String, String> forOrder({
    required String customerName,
    required double totalAmount,
    required String orderId,
    required String businessName,
    String currency = '₺',
    List<String>? itemNames,
  }) {
    return {
      'customer': customerName,
      'amount': _fmt(totalAmount, currency),
      'paid': _fmt(0, currency),
      'debt': '0,00 $currency',
      'id': orderId,
      'business': businessName,
      'date': _today(),
      'items': itemNames?.join(', ') ?? '',
      'discount': _fmt(0, currency),
    };
  }

  static String _fmt(double amount, String currency) {
    final s = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$s $currency';
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.'
        '${now.year}';
  }
}

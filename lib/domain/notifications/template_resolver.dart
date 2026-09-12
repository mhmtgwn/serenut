// lib/domain/notifications/template_resolver.dart
// Serenut OS — SMS Template Resolver
// Reads active template from Settings.smsTemplate JSON,
// resolves {variable} tokens, returns final message string.
// Created: 01 Jul 2026

import 'dart:convert';
import 'package:serenutos/config/utils.dart';
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

/// Canonical, rich default templates for WhatsApp (zero Meta dependency, formatted for Evolution API)
const kDefaultWhatsAppTemplates = <String, String>{
  kSmsEventOrderCreated: '''🛎️ *Siparişiniz Alındı*

Sayın *{customer}*,
#{id} numaralı siparişiniz başarıyla alınmış ve sıraya eklenmiştir.

📦 *Sipariş İçeriği:*
{items}

▫️ *Sipariş Tutarı:* *{amount}*
📅 *Tarih:* {date}

Siparişiniz hazırlanmaya başladığında tekrar bilgilendirileceksiniz.
Bizi tercih ettiğiniz için teşekkür ederiz!
*{business}*''',
  _kLegacyOrder: '''🛎️ *Siparişiniz Alındı*

Sayın *{customer}*,
#{id} numaralı siparişiniz başarıyla alınmış ve sıraya eklenmiştir.

📦 *Sipariş İçeriği:*
{items}

▫️ *Sipariş Tutarı:* *{amount}*
📅 *Tarih:* {date}

Siparişiniz hazırlanmaya başladığında tekrar bilgilendirileceksiniz.
Bizi tercih ettiğiniz için teşekkür ederiz!
*{business}*''',
  kSmsEventOrderPreparing: '''👨‍🍳 *Siparişiniz Hazırlanıyor*

Sayın *{customer}*,
#{id} numaralı siparişiniz şu anda özenle hazırlanmaktadır.

En kısa sürede tamamlanıp hazır hale getirilecektir.
*{business}*''',
  kSmsEventOrderReady: '''🎉 *Siparişiniz Hazır!*

Sayın *{customer}*,
#{id} numaralı siparişiniz hazır durumdadır.

▫️ *Sipariş No:* #{id}
▫️ *Toplam Tutar:* *{amount}*

İşletmemizden teslim alabilirsiniz. Afiyet olsun, iyi günlerde kullanın!
*{business}*''',
  kSmsEventOrderDelivered: '''✨ *Sipariş Teslim Edildi*

Sayın *{customer}*,
#{id} numaralı siparişiniz teslim edilmiştir.

Bizi tercih ettiğiniz için teşekkür ederiz. Tekrar görüşmek dileğiyle!
*{business}*''',
  kSmsEventOrderCancelled: '''❌ *Sipariş İptal Bildirimi*

Sayın *{customer}*,
#{id} numaralı siparişiniz iptal edilmiştir.

Herhangi bir sorunuz veya ayrıntılı bilgi için bizimle iletişime geçebilirsiniz.
*{business}*''',
  kSmsEventSaleCreated: '''🧾 *Alışveriş Fişi*

Sayın *{customer}*,
Alışverişiniz başarıyla tamamlanmıştır.

▫️ *Fiş No:* #{id}
▫️ *Tarih:* {date}

🛍️ *Satın Alınan Ürünler:*
{items}

▫️ *Ödenen:* *{paid}*
▫️ *Toplam Tutar:* *{amount}*

Bizi tercih ettiğiniz için teşekkür eder, iyi günlerde kullanmanızı dileriz.
*{business}*''',
  _kLegacySale: '''🧾 *Alışveriş Fişi*

Sayın *{customer}*,
Alışverişiniz başarıyla tamamlanmıştır.

▫️ *Fiş No:* #{id}
▫️ *Tarih:* {date}

🛍️ *Satın Alınan Ürünler:*
{items}

▫️ *Ödenen:* *{paid}*
▫️ *Toplam Tutar:* *{amount}*

Bizi tercih ettiğiniz için teşekkür eder, iyi günlerde kullanmanızı dileriz.
*{business}*''',
  kSmsEventDebtCreated: '''📋 *Cari Hesap Bilgilendirmesi*

Sayın *{customer}*,
#{id} numaralı vadeli alışveriş işleminiz cari hesabınıza işlenmiştir.

▫️ *İşlem Tutarı:* {amount}
▫️ *Eklenen Borç:* *{debt}*
▫️ *Güncel Toplam Bakiyeniz:* *{balance}*

Detaylı hesap ekstresi ve mutabakat için bizimle iletişime geçebilirsiniz.
*{business}*''',
  _kLegacyDebt: '''📋 *Cari Hesap Bilgilendirmesi*

Sayın *{customer}*,
#{id} numaralı vadeli alışveriş işleminiz cari hesabınıza işlenmiştir.

▫️ *İşlem Tutarı:* {amount}
▫️ *Eklenen Borç:* *{debt}*
▫️ *Güncel Toplam Bakiyeniz:* *{balance}*

Detaylı hesap ekstresi ve mutabakat için bizimle iletişime geçebilirsiniz.
*{business}*''',
  kSmsEventCollectionRecorded: '''✅ *Tahsilat Makbuzu*

Sayın *{customer}*,
Yapmış olduğunuz ödeme başarıyla tahsil edilmiş ve hesabınıza işlenmiştir.

▫️ *Makbuz No:* #{id}
▫️ *Tahsil Edilen:* *{amount}*
▫️ *Kalan Bakiyeniz:* *{debt}*
📅 *Tarih:* {date}

Ödemeniz için teşekkür ederiz.
*{business}*''',
  _kLegacyCollection: '''✅ *Tahsilat Makbuzu*

Sayın *{customer}*,
Yapmış olduğunuz ödeme başarıyla tahsil edilmiş ve hesabınıza işlenmiştir.

▫️ *Makbuz No:* #{id}
▫️ *Tahsil Edilen:* *{amount}*
▫️ *Kalan Bakiyeniz:* *{debt}*
📅 *Tarih:* {date}

Ödemeniz için teşekkür ederiz.
*{business}*''',
  'balance_reminder': '''🔔 *Bakiye Hatırlatması*

Sayın *{customer}*,
İşletmemizdeki cari hesabınızın güncel durum özeti aşağıdadır:

▫️ *Güncel Vadeli Bakiye:* *{balance}*
📅 *Tarih:* {date}

Ödeme ve mutabakat işlemleriniz için işletmemizle iletişime geçebilirsiniz.
Sağlıklı ve bereketli günler dileriz.
*{business}*''',
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

    final templateText = _findTemplate(
      eventType,
      templateStr,
      channel: NotificationTemplateChannel.sms,
    );
    if (templateText == null) return null;

    return _fillTokens(templateText, vars, isWhatsApp: false);
  }

  /// Check if [eventType] template exists and is enabled.
  bool isEnabled({required String eventType, required Settings settings}) {
    if (!settings.smsEnabled) return false;
    final t = settings.smsTemplate;
    if (t == null || t.trim().isEmpty) return false;
    return _findTemplate(
          eventType,
          t,
          channel: NotificationTemplateChannel.sms,
        ) !=
        null;
  }

  /// Resolves the local preview/fallback text only when WhatsApp is enabled
  /// for this event. WhatsApp itself uses the approved Meta template; this
  /// text is kept for the local outbox and delivery history.
  String? resolveWhatsApp({
    required String eventType,
    required Settings settings,
    required Map<String, String> vars,
  }) {
    final templateStr = settings.smsTemplate;
    if (templateStr == null || templateStr.trim().isEmpty) return null;
    final templateText = _findTemplate(
      eventType,
      templateStr,
      channel: NotificationTemplateChannel.whatsapp,
    );
    return templateText == null
        ? null
        : _fillTokens(templateText, vars, isWhatsApp: true);
  }

  static String formatCurrency(double amount, String currency) =>
      SmsTemplateVars._fmt(amount, currency);

  // ── Private ────────────────────────────────────────────────────────────────

  String? _findTemplate(
    String eventType,
    String templateJson, {
    required NotificationTemplateChannel channel,
  }) {
    try {
      final decoded = jsonDecode(templateJson);
      if (decoded is! List) return null;

      // Try new format ID first, then legacy alias
      final candidateIds =
          [eventType, _legacyAliases[eventType]].whereType<String>().toList();

      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        if (id == null || !candidateIds.contains(id)) continue;

        if (channel == NotificationTemplateChannel.whatsapp) {
          final enabled = item['whatsapp_enabled'];
          if (enabled != true) return null;

          final customWa = item['whatsapp_template']?.toString();
          if (customWa != null && customWa.trim().isNotEmpty) {
            return customWa;
          }

          final legacyTpl = item['template']?.toString();
          if (legacyTpl != null && legacyTpl.trim().isNotEmpty) {
            return legacyTpl;
          }

          return kDefaultWhatsAppTemplates[id] ??
              kDefaultWhatsAppTemplates[eventType] ??
              kDefaultWhatsAppTemplates[_legacyAliases[eventType]];
        } else {
          // SMS channel
          final enabled = item['sms_enabled'] ?? item['enabled'];
          if (enabled != true) return null;
          final template =
              item['sms_template']?.toString() ?? item['template']?.toString();
          if (template != null && template.trim().isNotEmpty) {
            return template;
          }
        }
      }
    } catch (_) {
      // Malformed JSON — silent
    }
    return null;
  }

  String _fillTokens(
    String template,
    Map<String, String> vars, {
    bool isWhatsApp = false,
  }) {
    var result = template;
    vars.forEach((key, value) {
      if (key == 'items') {
        final replacement = isWhatsApp
            ? (vars['whatsapp_items'] ?? value)
            : (vars['sms_items'] ?? value);
        result = result.replaceAll('{$key}', replacement);
      } else if (key != 'whatsapp_items' && key != 'sms_items') {
        result = result.replaceAll('{$key}', value);
      }
    });
    return result;
  }
}

enum NotificationTemplateChannel { sms, whatsapp }

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
    final (smsItems, whatsappItems) = _formatItems(itemNames);
    return {
      'customer': customerName,
      'amount': _fmt(totalAmount, currency),
      'paid': _fmt(paidAmount, currency),
      'debt': _fmt(
        (totalAmount - paidAmount).clamp(0, double.maxFinite),
        currency,
      ),
      'id': saleId.toShortId,
      'business': businessName,
      'date': _today(),
      'items': smsItems,
      'sms_items': smsItems,
      'whatsapp_items': whatsappItems,
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
      'id': saleId.toShortId,
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
      'id': transactionId.toShortId,
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
    final (smsItems, whatsappItems) = _formatItems(itemNames);
    return {
      'customer': customerName,
      'amount': _fmt(totalAmount, currency),
      'paid': _fmt(0, currency),
      'debt': '0,00 $currency',
      'id': orderId.toShortId,
      'business': businessName,
      'date': _today(),
      'items': smsItems,
      'sms_items': smsItems,
      'whatsapp_items': whatsappItems,
      'discount': _fmt(0, currency),
    };
  }

  static (String, String) _formatItems(List<String>? itemNames) {
    if (itemNames == null || itemNames.isEmpty) {
      return ('', '');
    }
    // SMS: comma-separated without prices (to conserve SMS character limits)
    final sms = itemNames.map((line) => line.split(' — ').first.trim()).join(', ');
    // WhatsApp: bulleted items with full details and price
    final whatsapp = itemNames.map((line) => '▫️ $line').join('\n');
    return (sms, whatsapp);
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

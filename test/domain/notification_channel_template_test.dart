import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/notifications/template_resolver.dart';

Settings _settings(
    {required bool smsEnabled, required List<Object?> templates}) {
  return Settings(
    businessName: 'Örnek İşletme',
    businessPhone: '05550000000',
    businessAddress: 'Test',
    smsEnabled: smsEnabled,
    smsTemplate: jsonEncode(templates),
  );
}

void main() {
  const resolver = TemplateResolver();
  const variables = {'customer': 'Ayşe', 'amount': '250,00 ₺'};

  test('SMS and WhatsApp can be enabled independently for the same event', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'sale_created',
        'sms_template': 'SMS: {customer}, toplam {amount}',
        'whatsapp_template': 'WA: {customer}, toplam {amount}',
        'enabled': true,
        'sms_enabled': false,
        'whatsapp_enabled': true,
      }
    ]);

    expect(
      resolver.resolve(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        vars: variables,
      ),
      isNull,
    );
    expect(
      resolver.resolveWhatsApp(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        vars: variables,
      ),
      'WA: Ayşe, toplam 250,00 ₺',
    );
  });

  test('legacy enabled flag remains an SMS-only setting', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'sale',
        'template': 'Satış {amount}',
        'enabled': true,
      }
    ]);

    expect(
      resolver.resolve(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        vars: variables,
      ),
      'Satış 250,00 ₺',
    );
    expect(
      resolver.resolveWhatsApp(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        vars: variables,
      ),
      isNull,
    );
  });

  test('global SMS switch does not disable an enabled WhatsApp event', () {
    final settings = _settings(smsEnabled: false, templates: [
      {
        'id': 'order_ready',
        'whatsapp_template': 'WA: {customer}, siparişiniz hazır.',
        'sms_enabled': true,
        'whatsapp_enabled': true,
      }
    ]);

    expect(
      resolver.resolve(
        eventType: kSmsEventOrderReady,
        settings: settings,
        vars: variables,
      ),
      isNull,
    );
    expect(
      resolver.resolveWhatsApp(
        eventType: kSmsEventOrderReady,
        settings: settings,
        vars: variables,
      ),
      'WA: Ayşe, siparişiniz hazır.',
    );
  });

  test('resolves distinct sms_template and whatsapp_template for the same event', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'sale_created',
        'sms_template': 'SMS: {customer}, {amount}',
        'whatsapp_template': 'WA: {customer}, {amount}',
        'sms_enabled': true,
        'whatsapp_enabled': true,
      }
    ]);

    expect(
      resolver.resolve(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        vars: variables,
      ),
      'SMS: Ayşe, 250,00 ₺',
    );
    expect(
      resolver.resolveWhatsApp(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        vars: variables,
      ),
      'WA: Ayşe, 250,00 ₺',
    );
  });

  test('WhatsApp rejects legacy SMS template and uses rich kDefaultWhatsAppTemplates', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'sale_created',
        'template': 'Merhaba {customer}, {id} nolu işlem tamamlandı. {business}',
        'sms_template': 'Merhaba {customer}, {id} nolu işlem tamamlandı. {business}',
        'sms_enabled': true,
        'whatsapp_enabled': true,
      }
    ]);

    final wa = resolver.resolveWhatsApp(
      eventType: kSmsEventSaleCreated,
      settings: settings,
      vars: {
        'customer': 'Ayşe',
        'amount': '250,00 ₺',
        'paid': '250,00 ₺',
        'id': '101',
        'date': '12.09.2026',
        'business': 'Test İşletme',
      },
    );
    expect(wa, contains('🧾 *Alışveriş Fişi*'));
    expect(wa, isNot(contains('Merhaba Ayşe')));
  });

  test('Order WhatsApp template includes discount and note when present', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'order_created',
        'whatsapp_enabled': true,
      }
    ]);

    final vars = SmsTemplateVars.forOrder(
      customerName: 'Mehmet Kaya',
      totalAmount: 310.0,
      orderId: 'ORD-555',
      businessName: 'Lezzet Dünyası',
      itemNames: ['2 x Karışık Pizza — 360,00 ₺'],
      discountAmount: 50.0,
      note: 'Kapıda teslim ediniz, acısız olsun.',
    );

    final wa = resolver.resolveWhatsApp(
      eventType: kSmsEventOrderCreated,
      settings: settings,
      vars: vars,
    );

    expect(wa, isNotNull);
    expect(wa, contains('🛎️ *Siparişiniz Alındı*'));
    expect(wa, contains('Mehmet Kaya'));
    expect(wa, contains('▫️ *İndirim:* -50,00 ₺'));
    expect(wa, contains('▫️ *Sipariş Tutarı:* *310,00 ₺*'));
    expect(wa, contains('📝 *Sipariş Notu:*'));
    expect(wa, contains('Kapıda teslim ediniz, acısız olsun.'));
  });

  test('Order WhatsApp template omits discount and note cleanly when absent', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'order_created',
        'whatsapp_enabled': true,
      }
    ]);

    final vars = SmsTemplateVars.forOrder(
      customerName: 'Fatma Demir',
      totalAmount: 200.0,
      orderId: 'ORD-777',
      businessName: 'Lezzet Dünyası',
      itemNames: ['1 x Burger Menü — 200,00 ₺'],
      discountAmount: 0.0,
      note: null,
    );

    final wa = resolver.resolveWhatsApp(
      eventType: kSmsEventOrderCreated,
      settings: settings,
      vars: vars,
    );

    expect(wa, isNotNull);
    expect(wa, contains('🛎️ *Siparişiniz Alındı*'));
    expect(wa, isNot(contains('İndirim')));
    expect(wa, isNot(contains('Sipariş Notu')));
    expect(wa, contains('▫️ *Sipariş Tutarı:* *200,00 ₺*'));
  });

  test('Sale WhatsApp template includes discount when present', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'sale_created',
        'whatsapp_enabled': true,
      }
    ]);

    final vars = SmsTemplateVars.forSale(
      customerName: 'Ali Veli',
      totalAmount: 180.0,
      paidAmount: 180.0,
      saleId: 'sale-999',
      businessName: 'Serenut POS',
      itemNames: ['1 x Pantolon — 200,00 ₺'],
      discountAmount: 20.0,
      note: 'Müşteri kartı indirimi uygulandı',
    );

    final wa = resolver.resolveWhatsApp(
      eventType: kSmsEventSaleCreated,
      settings: settings,
      vars: vars,
    );

    expect(wa, isNotNull);
    expect(wa, contains('🧾 *Alışveriş Fişi*'));
    expect(wa, contains('▫️ *İndirim:* -20,00 ₺'));
    expect(wa, contains('▫️ *Toplam Tutar:* *180,00 ₺*'));
    expect(wa, contains('Müşteri kartı indirimi uygulandı'));
  });

  test('Balance reminder resolves for both SMS and WhatsApp correctly', () {
    final settings = _settings(smsEnabled: true, templates: [
      {
        'id': 'balance_reminder',
        'sms_enabled': true,
        'whatsapp_enabled': true,
      }
    ]);

    final vars = SmsTemplateVars.forBalanceReminder(
      customerName: 'Fatma Şahin',
      balance: 1450.0,
      businessName: 'Serenut POS',
      currency: '₺',
    );

    final sms = resolver.resolveSms(
      eventType: kSmsEventBalanceReminder,
      settings: settings,
      vars: vars,
    );
    final wa = resolver.resolveWhatsApp(
      eventType: kSmsEventBalanceReminder,
      settings: settings,
      vars: vars,
    );

    expect(sms, isNotNull);
    expect(sms, contains('Fatma Şahin'));
    expect(sms, contains('1450,00 ₺'));

    expect(wa, isNotNull);
    expect(wa, contains('🔔 *Bakiye Hatırlatması*'));
    expect(wa, contains('Fatma Şahin'));
    expect(wa, contains('1450,00 ₺'));
    expect(wa, contains('Serenut POS'));
  });
}

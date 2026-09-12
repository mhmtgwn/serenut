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
}

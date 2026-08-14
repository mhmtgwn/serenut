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
        'template': 'Merhaba {customer}, toplam {amount}',
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
      'Merhaba Ayşe, toplam 250,00 ₺',
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
        'template': '{customer}, siparişiniz hazır.',
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
      'Ayşe, siparişiniz hazır.',
    );
  });
}

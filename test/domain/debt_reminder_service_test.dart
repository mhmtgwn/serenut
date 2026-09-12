import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/domain/notifications/template_resolver.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/debt_reminder_service.dart';
import 'package:serenutos/domain/services/sms_service.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';
import 'package:serenutos/infrastructure/sync_v4/whatsapp_notification_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockCustomerRepository implements ICustomerRepository {
  final List<CustomerEntity> _customers;
  MockCustomerRepository(this._customers);

  @override
  Future<List<CustomerEntity>> findAll() async => _customers;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSmsService extends SmsService {
  final List<({String phone, String message})> sent = [];
  bool shouldSucceed = true;

  MockSmsService() : super();

  @override
  Future<bool> sendSms(String phone, String message) async {
    sent.add((phone: phone, message: message));
    return shouldSucceed;
  }
}

class MockSmsLogRepository extends SmsLogRepository {
  final Map<String, DateTime> _lastReminders = {};
  final List<SmsLogEntry> logs = [];

  MockSmsLogRepository() : super(DatabaseManager());

  @override
  Future<DateTime?> getLastReminderDate(String phone) async {
    return _lastReminders[phone];
  }

  @override
  Future<int> insertLog(SmsLogEntry log) async {
    logs.add(log);
    if (log.sentAt != null) {
      _lastReminders[log.phone] = log.sentAt!;
    }
    return 1;
  }

  @override
  Future<int> updateStatus(
    String id,
    SmsLogStatus status, {
    DateTime? sentAt,
    String? errorMessage,
  }) async {
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSmsLogRepository mockSmsLogRepo;
  late MockSmsService mockSmsService;
  late WhatsappNotificationOutbox whatsappOutbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockSmsLogRepo = MockSmsLogRepository();
    mockSmsService = MockSmsService();
    final apiClient = ApiClient();
    whatsappOutbox = WhatsappNotificationOutbox(apiClient);
  });

  test('DebtReminderService filters debtors by minAmount and repeatInterval', () async {
    final customers = [
      CustomerEntity(
        id: 'c1',
        name: 'Ahmet',
        email: 'ahmet@test.com',
        phone: '05551112233',
        balance: -250.0, // Borçlu: 250 TL
        createdAt: DateTime.now(),
      ),
      CustomerEntity(
        id: 'c2',
        name: 'Mehmet',
        email: 'mehmet@test.com',
        phone: '05552223344',
        balance: -50.0, // Borçlu ama minAmount (100 TL) altında
        createdAt: DateTime.now(),
      ),
      CustomerEntity(
        id: 'c3',
        name: 'Ayşe',
        email: 'ayse@test.com',
        phone: '05553334455',
        balance: 100.0, // Alacaklı
        createdAt: DateTime.now(),
      ),
      CustomerEntity(
        id: 'c4',
        name: 'Fatma (Hatırlatılmış)',
        email: 'fatma@test.com',
        phone: '05554445566',
        balance: -500.0, // Borçlu ama dün hatırlatma aldı
        createdAt: DateTime.now(),
      ),
    ];

    // c4 için dün gönderilmiş log ekle
    await mockSmsLogRepo.insertLog(
      SmsLogEntry(
        id: 'log1',
        phone: '05554445566',
        eventType: 'balance_reminder',
        message: 'Hatırlatma',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        sentAt: DateTime.now().subtract(const Duration(days: 1)),
        status: SmsLogStatus.sent,
      ),
    );

    final service = DebtReminderService(
      customerRepository: MockCustomerRepository(customers),
      smsLogRepository: mockSmsLogRepo,
      smsService: mockSmsService,
      whatsappOutbox: whatsappOutbox,
    );

    final settings = Settings(
      businessName: 'Deneme İşletmesi',
      businessPhone: '05550000000',
      businessAddress: 'Adres',
      smsAutoDebtReminderEnabled: true,
      smsAutoDebtReminderMinAmount: 100.0,
      autoDebtReminderRepeatDays: 7, // 7 gün dolmadan tekrar gönderme
      autoDebtReminderChannel: 'both',
    );

    final eligible = await service.getEligibleDebtors(settings: settings);

    // Sadece Ahmet (c1) uygun olmalı; Mehmet min altında, Ayşe alacaklı, Fatma dün hatırlatıldı
    expect(eligible.length, 1);
    expect(eligible.first.id, 'c1');
  });

  test('DebtReminderService sends to both SMS and WhatsApp correctly', () async {
    final customer = CustomerEntity(
      id: 'c1',
      name: 'Ali Veli',
      email: 'ali@test.com',
      phone: '05551112233',
      balance: -300.0,
      createdAt: DateTime.now(),
    );

    final service = DebtReminderService(
      customerRepository: MockCustomerRepository([customer]),
      smsLogRepository: mockSmsLogRepo,
      smsService: mockSmsService,
      whatsappOutbox: whatsappOutbox,
    );

    final settings = Settings(
      businessName: 'Deneme İşletmesi',
      businessPhone: '05550000000',
      businessAddress: 'Adres',
      currency: '₺',
      smsEnabled: true,
      smsTemplate: jsonEncode([
        {
          'id': 'balance_reminder',
          'sms_enabled': true,
          'whatsapp_enabled': true,
        }
      ]),
      autoDebtReminderChannel: 'both',
    );

    final res = await service.sendReminderToCustomer(
      customer: customer,
      settings: settings,
    );

    expect(res.smsSuccess, isTrue);
    expect(mockSmsService.sent.length, 1);
    expect(mockSmsService.sent.first.phone, '05551112233');
    expect(mockSmsService.sent.first.message, contains('300,00 ₺'));
    expect(res.waSuccess, isTrue);
  });
}

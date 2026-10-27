import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serenutos/domain/interfaces/earsiv_provider.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';
import 'package:serenutos/domain/services/gib_invoice_service.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_invoice_repository.dart';
import 'package:serenutos/infrastructure/services/gib_earsiv_client.dart';

class MockInvoiceRepository implements IGibInvoiceRepository {
  final Map<String, GibInvoiceRecord> storage = {};

  @override
  Future<void> saveInvoice(GibInvoiceRecord record) async {
    storage[record.id] = record;
  }

  @override
  Future<GibInvoiceRecord?> findById(String id) async {
    return storage[id];
  }

  @override
  Future<GibInvoiceRecord?> findByGibUuid(String gibUuid) async {
    return storage.values.cast<GibInvoiceRecord?>().firstWhere(
          (r) => r?.gibUuid == gibUuid,
          orElse: () => null,
        );
  }

  @override
  Future<GibInvoiceRecord?> findBySaleId(String saleId) async {
    return storage.values.cast<GibInvoiceRecord?>().firstWhere(
          (r) => r?.saleId == saleId,
          orElse: () => null,
        );
  }

  @override
  Future<List<GibInvoiceRecord>> getInvoicesByCustomerId(String customerId) async {
    return storage.values.where((r) => r.customerId == customerId).toList();
  }

  @override
  Future<List<GibInvoiceRecord>> getAllInvoices({int limit = 50, int offset = 0}) async {
    return storage.values.toList();
  }

  @override
  Future<void> updateStatus({
    required String id,
    required GibInvoiceStatus status,
    String? invoiceNumber,
    String? htmlContent,
    DateTime? signedAt,
  }) async {
    final existing = storage[id];
    if (existing != null) {
      storage[id] = existing.copyWith(
        status: status,
        signedAt: signedAt ?? existing.signedAt,
      );
    }
  }

  @override
  Future<void> deleteInvoice(String id) async {
    storage.remove(id);
  }
}

class MockCustomIntegrator implements IEArsivProvider {
  final List<String> signedUuids = [];

  @override
  String get providerId => 'custom_integrator';

  @override
  String get displayName => 'Özel Entegratör';

  @override
  Future<bool> testConnection({required String username, required String password}) async => true;

  @override
  Future<String> login({required String username, required String password}) async => 'mock-jwt-token';

  @override
  Future<String> createDraftInvoice({
    required String token,
    required GibInvoiceRecipient recipient,
    required List<GibInvoiceItem> items,
    required double totalWithoutVat,
    required double totalVat,
    required double totalAmount,
    GibInvoiceType invoiceType = GibInvoiceType.satis,
    String? note,
    String? predefinedUuid,
  }) async => predefinedUuid ?? 'mock-uuid-1';

  @override
  Future<String> requestSmsCode({required String token}) async => '5551234567';

  @override
  Future<bool> verifySmsCodeAndSign({
    required String token,
    required String smsCode,
    required String invoiceUuid,
  }) async {
    signedUuids.add(invoiceUuid);
    return true;
  }

  @override
  Future<bool> verifySmsCodeAndSignBatch({
    required String token,
    required String smsCode,
    required List<String> invoiceUuids,
  }) async {
    signedUuids.addAll(invoiceUuids);
    return true;
  }

  @override
  Future<String> getInvoiceHtml({required String token, required String invoiceUuid, bool isApproved = true}) async =>
      '<html><body>Fatura $invoiceUuid</body></html>';

  @override
  Future<bool> cancelInvoice({
    required String token,
    required String invoiceUuid,
    required String reason,
  }) async => true;
}

void main() {
  test('GibEArsivClient implements IEArsivProvider interface contract', () {
    final client = GibEArsivClient(isTestMode: true);
    expect(client, isA<IEArsivProvider>());
    expect(client.providerId, 'gib_portal');
    expect(client.displayName, contains('Test'));
  });

  test('GibEArsivClient sends batch invoice UUIDs to GİB dispatch endpoint', () async {
    Map<String, dynamic>? sentPayload;

    final mockHttpClient = MockClient((request) async {
      final body = request.bodyFields;
      if (body['cmd'] == 'EARSIV_PORTAL_SMSSIFRE_DOGRULA') {
        sentPayload = jsonDecode(body['jp']!) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(jsonEncode({'data': 'başarıyla imzalandı'})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(jsonEncode({'error': 'unknown_cmd'}), 400);
    });

    final client = GibEArsivClient(httpClient: mockHttpClient, isTestMode: true);
    final batchUuids = ['uuid-111', 'uuid-222', 'uuid-333'];

    final result = await client.verifySmsCodeAndSignBatch(
      token: 'test-token',
      smsCode: '123456',
      invoiceUuids: batchUuids,
    );

    expect(result, isTrue);
    expect(sentPayload, isNotNull);
    expect(sentPayload?['smsSifre'], '123456');

    final imzalanacaklar = sentPayload?['imzalanacaklar'] as List;
    expect(imzalanacaklar.length, 3);
    expect(imzalanacaklar[0]['faturaUuid'], 'uuid-111');
    expect(imzalanacaklar[1]['faturaUuid'], 'uuid-222');
    expect(imzalanacaklar[2]['faturaUuid'], 'uuid-333');
  });

  test('GibInvoiceService performs atomic batch signing using IEArsivProvider abstraction', () async {
    final mockProvider = MockCustomIntegrator();
    final mockRepo = MockInvoiceRepository();
    final service = GibInvoiceService(client: mockProvider, repository: mockRepo);

    // Seed 2 pending invoices
    final inv1 = GibInvoiceRecord(
      id: 'inv-1',
      gibUuid: 'gib-uuid-1',
      recipient: const GibInvoiceRecipient(titleOrName: 'Müşteri 1', identifier: '11111111111'),
      items: const [],
      totalWithoutVat: 100,
      totalVat: 20,
      totalAmount: 120,
      status: GibInvoiceStatus.pendingSms,
      createdAt: DateTime.now(),
    );
    final inv2 = GibInvoiceRecord(
      id: 'inv-2',
      gibUuid: 'gib-uuid-2',
      recipient: const GibInvoiceRecipient(titleOrName: 'Müşteri 2', identifier: '22222222222'),
      items: const [],
      totalWithoutVat: 200,
      totalVat: 40,
      totalAmount: 240,
      status: GibInvoiceStatus.pendingSms,
      createdAt: DateTime.now(),
    );

    await mockRepo.saveInvoice(inv1);
    await mockRepo.saveInvoice(inv2);

    final signedBatch = await service.verifySmsAndSignBatch(
      username: 'user',
      password: 'pwd',
      invoices: [
        (invoiceId: 'inv-1', gibUuid: 'gib-uuid-1'),
        (invoiceId: 'inv-2', gibUuid: 'gib-uuid-2'),
      ],
      smsCode: '987654',
    );

    expect(signedBatch.length, 2);
    expect(signedBatch[0].status, GibInvoiceStatus.signed);
    expect(signedBatch[1].status, GibInvoiceStatus.signed);

    expect(mockProvider.signedUuids, containsAll(['gib-uuid-1', 'gib-uuid-2']));

    final record1 = await mockRepo.findById('inv-1');
    expect(record1?.status, GibInvoiceStatus.signed);
    expect(record1?.signedAt, isNotNull);
  });
}

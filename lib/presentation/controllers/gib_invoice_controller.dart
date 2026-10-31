import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';
import 'package:serenutos/providers/gib_invoice_providers.dart';

final gibInvoiceControllerProvider = Provider<GibInvoiceController>((ref) {
  return GibInvoiceController(ref);
});

class GibInvoiceController {
  final Ref _ref;

  GibInvoiceController(this._ref);

  Future<bool> testConnection({
    required String username,
    required String password,
    bool? isTestMode,
  }) async {
    if (isTestMode != null) {
      _ref.read(gibEArsivClientProvider).isTestMode = isTestMode;
    }
    final service = _ref.read(gibInvoiceServiceProvider);
    return await service.testConnection(
      username: username,
      password: password,
    );
  }

  Future<GibInvoiceRecord> createAndSubmitDraft({
    required String username,
    required String password,
    required GibInvoiceRecipient recipient,
    required List<GibInvoiceItem> items,
    required num totalWithoutVat,
    required num totalVat,
    required num totalAmount,
    String? saleId,
    String? customerId,
    String? note,
  }) async {
    final service = _ref.read(gibInvoiceServiceProvider);
    final record = await service.createAndSubmitDraft(
      username: username,
      password: password,
      recipient: recipient,
      items: items,
      totalWithoutVat: totalWithoutVat.toDouble(),
      totalVat: totalVat.toDouble(),
      totalAmount: totalAmount.toDouble(),
      saleId: saleId,
      customerId: customerId,
      note: note,
    );
    _ref.invalidate(gibInvoiceListProvider);
    if (saleId != null) {
      _ref.invalidate(saleInvoiceProvider(saleId));
    }
    return record;
  }

  Future<String> requestSmsCode({
    required String username,
    required String password,
  }) async {
    final service = _ref.read(gibInvoiceServiceProvider);
    return await service.requestSmsCode(username: username, password: password);
  }

  Future<GibInvoiceRecord> verifySmsAndSign({
    required String username,
    required String password,
    required String invoiceId,
    required String gibUuid,
    required String smsCode,
  }) async {
    final service = _ref.read(gibInvoiceServiceProvider);
    final signed = await service.verifySmsAndSign(
      username: username,
      password: password,
      invoiceId: invoiceId,
      gibUuid: gibUuid,
      smsCode: smsCode,
    );
    _ref.invalidate(gibInvoiceListProvider);
    if (signed.saleId != null) {
      _ref.invalidate(saleInvoiceProvider(signed.saleId!));
    }
    return signed;
  }

  Future<List<GibInvoiceRecord>> getInvoices({int limit = 100}) async {
    final service = _ref.read(gibInvoiceServiceProvider);
    return await service.getInvoices(limit: limit);
  }

  Future<GibInvoiceRecord?> getInvoiceForSale(String saleId) async {
    final service = _ref.read(gibInvoiceServiceProvider);
    return await service.getInvoiceForSale(saleId);
  }

  Future<void> cancelInvoice({
    required String username,
    required String password,
    required String invoiceId,
    required String gibUuid,
    required String reason,
  }) async {
    final service = _ref.read(gibInvoiceServiceProvider);
    await service.cancelInvoice(
      username: username,
      password: password,
      invoiceId: invoiceId,
      gibUuid: gibUuid,
      reason: reason,
    );
    _ref.invalidate(gibInvoiceListProvider);
  }
}


// lib/domain/services/gib_invoice_service.dart
// Serenut OS — GİB e-Arşiv Fatura Üst Seviye Yönetim Servisi
// Fatura oluşturma, SMS imzalama, SQLite geçmişi ve WhatsApp paylaşımı

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';
import 'package:serenutos/infrastructure/services/gib_earsiv_client.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_invoice_repository.dart';

class GibInvoiceService {
  final GibEArsivClient _client;
  final IGibInvoiceRepository _repository;

  GibInvoiceService({
    required GibEArsivClient client,
    required IGibInvoiceRepository repository,
  })  : _client = client,
        _repository = repository;

  /// GİB Bağlantısını Test Et
  Future<bool> testConnection({
    required String username,
    required String password,
  }) async {
    try {
      final token = await _client.login(username: username, password: password);
      return token.isNotEmpty;
    } catch (e) {
      debugPrint('[GibInvoiceService] Bağlantı testi başarısız: $e');
      rethrow;
    }
  }

  /// 1. Adım: Taslak Faturayı Hazırla, Yerel Depoya Kaydet ve GİB'e Gönder
  Future<GibInvoiceRecord> createAndSubmitDraft({
    required String username,
    required String password,
    required GibInvoiceRecipient recipient,
    required List<GibInvoiceItem> items,
    required double totalWithoutVat,
    required double totalVat,
    required double totalAmount,
    String? saleId,
    String? customerId,
    String? note,
    GibInvoiceType invoiceType = GibInvoiceType.satis,
  }) async {
    final localId = const Uuid().v4();
    final gibUuid = const Uuid().v4().toLowerCase();

    // 1. GİB'e Giriş Yap
    final token = await _client.login(username: username, password: password);

    // 2. GİB Portale Taslak Olarak Gönder
    await _client.createDraftInvoice(
      token: token,
      recipient: recipient,
      items: items,
      totalWithoutVat: totalWithoutVat,
      totalVat: totalVat,
      totalAmount: totalAmount,
      invoiceType: invoiceType,
      note: note,
      predefinedUuid: gibUuid,
    );

    // 3. Yerel Kaydı Oluştur
    final record = GibInvoiceRecord(
      id: localId,
      gibUuid: gibUuid,
      saleId: saleId,
      customerId: customerId,
      recipient: recipient,
      items: items,
      totalWithoutVat: totalWithoutVat,
      totalVat: totalVat,
      totalAmount: totalAmount,
      invoiceType: invoiceType,
      status: GibInvoiceStatus.pendingSms,
      note: note,
      createdAt: DateTime.now(),
    );

    await _repository.saveInvoice(record);
    return record;
  }

  /// 2. Adım: Yetkili Telefonuna GİB SMS Şifresi Gönder
  Future<String> requestSmsCode({
    required String username,
    required String password,
  }) async {
    final token = await _client.login(username: username, password: password);
    return await _client.requestSmsCode(token: token);
  }

  /// 3. Adım: SMS Kodunu Doğrula ve Faturayı İmzala
  Future<GibInvoiceRecord> verifySmsAndSign({
    required String username,
    required String password,
    required String invoiceId,
    required String gibUuid,
    required String smsCode,
  }) async {
    final token = await _client.login(username: username, password: password);

    // GİB üzerinde resmi imzayı bas
    await _client.verifySmsAndSign(
      token: token,
      smsCode: smsCode,
      invoiceUuid: gibUuid,
    );

    // İmzalı resmi HTML çıktısını çek
    String? html;
    try {
      html = await _client.getInvoiceHtml(token: token, invoiceUuid: gibUuid);
    } catch (e) {
      debugPrint('[GibInvoiceService] HTML çıktısı çekilirken uyarı: $e');
    }

    final signedAt = DateTime.now();
    await _repository.updateStatus(
      id: invoiceId,
      status: GibInvoiceStatus.signed,
      htmlContent: html,
      signedAt: signedAt,
    );

    final updated = await _repository.findById(invoiceId);
    return updated!;
  }

  /// Fatura İptali
  Future<void> cancelInvoice({
    required String username,
    required String password,
    required String invoiceId,
    required String gibUuid,
    required String reason,
  }) async {
    final token = await _client.login(username: username, password: password);
    await _client.cancelInvoice(
      token: token,
      invoiceUuid: gibUuid,
      reason: reason,
    );

    await _repository.updateStatus(
      id: invoiceId,
      status: GibInvoiceStatus.cancelled,
    );
  }

  /// Fatura Geçmişi
  Future<List<GibInvoiceRecord>> getInvoices({int limit = 100}) {
    return _repository.getAllInvoices(limit: limit);
  }

  /// Satışa Ait Fatura Var mı?
  Future<GibInvoiceRecord?> getInvoiceForSale(String saleId) {
    return _repository.findBySaleId(saleId);
  }
}

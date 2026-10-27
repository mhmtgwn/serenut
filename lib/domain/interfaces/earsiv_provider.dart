// lib/domain/interfaces/earsiv_provider.dart
// Serenut OS — e-Arşiv Fatura Sağlayıcı Soyutlaması (Clean Architecture / Dependency Inversion)
// GİB Portal veya Özel Entegratörler (Nilvera, Sovos, EDM, Uyumsoft vb.) bu arayüz üzerinden çalışır.

import 'package:serenutos/domain/models/gib_invoice_models.dart';

abstract class IEArsivProvider {
  /// Sağlayıcı sistem kimliği ('gib_portal', 'nilvera', 'sovos', 'edm')
  String get providerId;

  /// Kullanıcı arayüzünde görünen sağlayıcı adı
  String get displayName;

  /// Sağlayıcı bağlantısını test et
  Future<bool> testConnection({
    required String username,
    required String password,
  });

  /// Sağlayıcıya giriş yap ve oturum token'ı al
  Future<String> login({
    required String username,
    required String password,
  });

  /// Taslak fatura oluştur
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
  });

  /// SMS Onay kodu talep et (GİB Portal doğrulama akışı için)
  Future<String> requestSmsCode({required String token});

  /// Tek bir faturayı SMS kodu ile resmi olarak imzala
  Future<bool> verifySmsCodeAndSign({
    required String token,
    required String smsCode,
    required String invoiceUuid,
  });

  /// Birden fazla faturayı tek bir SMS onay koduyla toplu imzala
  Future<bool> verifySmsCodeAndSignBatch({
    required String token,
    required String smsCode,
    required List<String> invoiceUuids,
  });

  /// Faturanın resmi HTML çıktısını al (Onaylanmış veya taslak önizleme)
  Future<String> getInvoiceHtml({
    required String token,
    required String invoiceUuid,
    bool isApproved = true,
  });

  /// Faturayı İptal Et / Sil
  Future<bool> cancelInvoice({
    required String token,
    required String invoiceUuid,
    required String reason,
  });
}

// lib/domain/models/gib_invoice_models.dart
// Serenut OS — GİB e-Arşiv Fatura Modelleri
// Resmi Gelir İdaresi Başkanlığı e-Arşiv Portal Entegrasyonu

import 'dart:convert';

/// GİB e-Arşiv Fatura Tipi
enum GibInvoiceType {
  satis('SATIS', 'Satış'),
  iade('IADE', 'İade'),
  istisna('ISTISNA', 'İstisna'),
  tevkifat('TEVKIFAT', 'Tevkifat');

  final String code;
  final String label;
  const GibInvoiceType(this.code, this.label);
}

/// Fatura Durumu
enum GibInvoiceStatus {
  draft('draft', 'Taslak'),
  pendingSms('pending_sms', 'SMS Onayı Bekliyor'),
  signed('signed', 'İmzalandı (Resmi)'),
  cancelled('cancelled', 'İptal Edildi'),
  failed('failed', 'Hata Oluştu');

  final String code;
  final String label;
  const GibInvoiceStatus(this.code, this.label);

  static GibInvoiceStatus fromCode(String code) {
    return GibInvoiceStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => GibInvoiceStatus.draft,
    );
  }
}

/// Alıcı Türü (Şahıs / Şirket / Nihai Tüketici)
enum GibRecipientType {
  individual('individual', 'Şahıs (TCKN)'),
  corporate('corporate', 'Tüzel Kişi / Şirket (VKN)'),
  consumer('consumer', 'Nihai Tüketici (11111111111)');

  final String code;
  final String label;
  const GibRecipientType(this.code, this.label);
}

/// GİB e-Arşiv Fatura Alıcı Bilgileri
class GibInvoiceRecipient {
  final String identifier; // TCKN (11 hane) veya VKN (10 hane) veya '11111111111'
  final String titleOrName; // Şirket unvanı veya Ad Soyad
  final String taxOffice; // Vergi Dairesi (Şirketler için zorunlu)
  final String address;
  final String district;
  final String city;
  final String? phone;
  final String? email;
  final GibRecipientType type;

  const GibInvoiceRecipient({
    required this.identifier,
    required this.titleOrName,
    this.taxOffice = '',
    this.address = '',
    this.district = '',
    this.city = '',
    this.phone,
    this.email,
    this.type = GibRecipientType.consumer,
  });

  /// 11111111111 Nihai Tüketici Fabrikası
  factory GibInvoiceRecipient.consumer({
    String name = 'Nihai Tüketici',
    String city = 'Türkiye',
    String address = '',
    String? phone,
  }) {
    return GibInvoiceRecipient(
      identifier: '11111111111',
      titleOrName: name,
      taxOffice: '',
      address: address,
      district: '',
      city: city,
      phone: phone,
      type: GibRecipientType.consumer,
    );
  }

  Map<String, dynamic> toMap() => {
        'identifier': identifier,
        'titleOrName': titleOrName,
        'taxOffice': taxOffice,
        'address': address,
        'district': district,
        'city': city,
        'phone': phone,
        'email': email,
        'type': type.code,
      };

  factory GibInvoiceRecipient.fromMap(Map<String, dynamic> map) {
    return GibInvoiceRecipient(
      identifier: map['identifier'] as String? ?? '11111111111',
      titleOrName: map['titleOrName'] as String? ?? 'Nihai Tüketici',
      taxOffice: map['taxOffice'] as String? ?? '',
      address: map['address'] as String? ?? '',
      district: map['district'] as String? ?? '',
      city: map['city'] as String? ?? '',
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      type: GibRecipientType.values.firstWhere(
        (e) => e.code == map['type'],
        orElse: () => GibRecipientType.consumer,
      ),
    );
  }
}

/// Fatura Kalemi (Satır)
class GibInvoiceItem {
  final String name;
  final double quantity;
  final String unit; // C62 = Adet, KGM = Kilogram, vb.
  final double unitPrice; // KDV hariç birim fiyat
  final double vatRate; // %0, %1, %10, %20
  final double discountAmount;

  const GibInvoiceItem({
    required this.name,
    required this.quantity,
    this.unit = 'C62', // Adet
    required this.unitPrice,
    this.vatRate = 20.0,
    this.discountAmount = 0.0,
  });

  /// KDV Hariç Tutar (İskonto Sonrası)
  double get lineTotalWithoutVat =>
      (quantity * unitPrice) - discountAmount;

  /// KDV Tutarı
  double get vatAmount => lineTotalWithoutVat * (vatRate / 100.0);

  /// KDV Dahil Toplam Satır Tutarı
  double get lineTotalWithVat => lineTotalWithoutVat + vatAmount;

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'unitPrice': unitPrice,
        'vatRate': vatRate,
        'discountAmount': discountAmount,
        'lineTotalWithoutVat': lineTotalWithoutVat,
        'vatAmount': vatAmount,
        'lineTotalWithVat': lineTotalWithVat,
      };

  factory GibInvoiceItem.fromMap(Map<String, dynamic> map) {
    return GibInvoiceItem(
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: map['unit'] as String? ?? 'C62',
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
      vatRate: (map['vatRate'] as num?)?.toDouble() ?? 20.0,
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Veritabanında Saklanan Fatura Kaydı
class GibInvoiceRecord {
  final String id; // Yerel ID (UUID)
  final String? gibUuid; // GİB e-Arşiv sistemindeki UUID (ETTN)
  final String? invoiceNumber; // GİB Fatura No (Örn: GIB2026000000001)
  final String? saleId; // İlişkili Satış ID
  final String? customerId; // İlişkili Müşteri ID
  final GibInvoiceRecipient recipient;
  final List<GibInvoiceItem> items;
  final double totalWithoutVat;
  final double totalVat;
  final double totalAmount; // KDV Dahil Genel Toplam
  final GibInvoiceType invoiceType;
  final GibInvoiceStatus status;
  final String? note;
  final String? htmlContent; // Resmi GİB Fatura HTML Çıktısı
  final DateTime createdAt;
  final DateTime? signedAt;

  const GibInvoiceRecord({
    required this.id,
    this.gibUuid,
    this.invoiceNumber,
    this.saleId,
    this.customerId,
    required this.recipient,
    required this.items,
    required this.totalWithoutVat,
    required this.totalVat,
    required this.totalAmount,
    this.invoiceType = GibInvoiceType.satis,
    this.status = GibInvoiceStatus.draft,
    this.note,
    this.htmlContent,
    required this.createdAt,
    this.signedAt,
  });

  GibInvoiceRecord copyWith({
    String? id,
    String? gibUuid,
    String? invoiceNumber,
    String? saleId,
    String? customerId,
    GibInvoiceRecipient? recipient,
    List<GibInvoiceItem>? items,
    double? totalWithoutVat,
    double? totalVat,
    double? totalAmount,
    GibInvoiceType? invoiceType,
    GibInvoiceStatus? status,
    String? note,
    String? htmlContent,
    DateTime? createdAt,
    DateTime? signedAt,
  }) {
    return GibInvoiceRecord(
      id: id ?? this.id,
      gibUuid: gibUuid ?? this.gibUuid,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      saleId: saleId ?? this.saleId,
      customerId: customerId ?? this.customerId,
      recipient: recipient ?? this.recipient,
      items: items ?? this.items,
      totalWithoutVat: totalWithoutVat ?? this.totalWithoutVat,
      totalVat: totalVat ?? this.totalVat,
      totalAmount: totalAmount ?? this.totalAmount,
      invoiceType: invoiceType ?? this.invoiceType,
      status: status ?? this.status,
      note: note ?? this.note,
      htmlContent: htmlContent ?? this.htmlContent,
      createdAt: createdAt ?? this.createdAt,
      signedAt: signedAt ?? this.signedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'gib_uuid': gibUuid,
        'invoice_number': invoiceNumber,
        'sale_id': saleId,
        'customer_id': customerId,
        'recipient_json': jsonEncode(recipient.toMap()),
        'items_json': jsonEncode(items.map((e) => e.toMap()).toList()),
        'total_without_vat': totalWithoutVat,
        'total_vat': totalVat,
        'total_amount': totalAmount,
        'invoice_type': invoiceType.code,
        'status': status.code,
        'note': note,
        'html_content': htmlContent,
        'created_at': createdAt.toIso8601String(),
        'signed_at': signedAt?.toIso8601String(),
      };

  factory GibInvoiceRecord.fromMap(Map<String, dynamic> map) {
    final recipientMap = jsonDecode(map['recipient_json'] as String? ?? '{}')
        as Map<String, dynamic>;
    final itemsList = (jsonDecode(map['items_json'] as String? ?? '[]')
            as List<dynamic>)
        .map((e) => GibInvoiceItem.fromMap(e as Map<String, dynamic>))
        .toList();

    return GibInvoiceRecord(
      id: map['id'] as String,
      gibUuid: map['gib_uuid'] as String?,
      invoiceNumber: map['invoice_number'] as String?,
      saleId: map['sale_id'] as String?,
      customerId: map['customer_id'] as String?,
      recipient: GibInvoiceRecipient.fromMap(recipientMap),
      items: itemsList,
      totalWithoutVat: (map['total_without_vat'] as num?)?.toDouble() ?? 0.0,
      totalVat: (map['total_vat'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      invoiceType: GibInvoiceType.values.firstWhere(
        (e) => e.code == map['invoice_type'],
        orElse: () => GibInvoiceType.satis,
      ),
      status: GibInvoiceStatus.fromCode(map['status'] as String? ?? 'draft'),
      note: map['note'] as String?,
      htmlContent: map['html_content'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      signedAt: map['signed_at'] != null
          ? DateTime.parse(map['signed_at'] as String)
          : null,
    );
  }
}

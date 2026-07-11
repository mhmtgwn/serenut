// lib/domain/models/settings.dart
// Settings = Runtime configuration (Domain Model)

class Settings {
  final int? id;
  
  // İşletme bilgisi
  final String businessName;
  final String businessPhone;
  final String businessAddress;
  final String? businessTaxId;
  final String? businessLogo;
  final String ownerName;
  final String? businessEmail;
  final String businessCity;
  final String businessDistrict;
  final String businessType;
  final String currency;          // ₺
  
  // Yazıcı ayarları
  final String? printerName;
  final String? printerIp;
  final int printerPort;
  final int paperWidth;           // mm (80mm termal)
  final bool printReceipt;
  final bool printQRCode;
  final bool printProductDetails;
  final bool printBarcode;
  final int printCopies;
  
  // KDV kategorileri (JSON string)
  final String vatCategories;     // JSON: [{"name":"Normal","rate":18}, ...]
  
  // SMS ayarları
  final bool smsEnabled;
  final String? smsProvider;      // 'twilio', 'local', etc.
  final String? smsApiKey;
  final String? smsTemplate;
  
  // QR Settings
  final bool qrEnabled;
  final String qrFormat;          // 'type|id|timestamp|customerId|amount|hash'
  
  // Diğer
  final bool debugMode;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Settings({
    this.id,
    required this.businessName,
    required this.businessPhone,
    required this.businessAddress,
    this.businessTaxId,
    this.businessLogo,
    this.ownerName = '',
    this.businessEmail,
    this.businessCity = '',
    this.businessDistrict = '',
    this.businessType = '',
    this.currency = '₺',
    this.printerName,
    this.printerIp,
    this.printerPort = 9100,
    this.paperWidth = 80,
    this.printReceipt = true,
    this.printQRCode = true,
    this.printProductDetails = true,
    this.printBarcode = true,
    this.printCopies = 1,
    this.vatCategories = '[]',
    this.smsEnabled = false,
    this.smsProvider,
    this.smsApiKey,
    this.smsTemplate,
    this.qrEnabled = true,
    this.qrFormat = 'type|id|timestamp|customerId|amount|hash',
    this.debugMode = false,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Validation
  bool get isValid => businessName.isNotEmpty && businessPhone.isNotEmpty;

  factory Settings.fromMap(Map<String, dynamic> map) {
    return Settings(
      id: map['id'] as int?,
      businessName: map['business_name'] ?? map['company_name'] as String,
      businessPhone: map['business_phone'] ?? map['company_phone'] as String,
      businessAddress: map['business_address'] ?? map['company_address'] as String,
      businessTaxId: map['business_tax_id'] ?? map['company_tax_number'] as String?,
      businessLogo: map['business_logo'] as String?,
      ownerName: map['owner_name'] as String? ?? '',
      businessEmail: map['business_email'] as String?,
      businessCity: map['business_city'] as String? ?? '',
      businessDistrict: map['business_district'] as String? ?? '',
      businessType: map['business_type'] as String? ?? '',
      currency: map['currency'] as String? ?? '₺',

      printerName: map['printer_name'] as String?,
      printerIp: map['printer_ip'] as String?,
      printerPort: (map['printer_port'] as int?) ?? 9100,
      paperWidth: (map['paper_width'] as int?) ?? 80,
      printReceipt: (map['print_receipt'] as int?) == 1,
      printQRCode: (map['print_qr_code'] as int?) == 1,
      printProductDetails: (map['print_product_details'] as int?) == 1,
      printBarcode: (map['print_barcode'] as int?) == 1,
      printCopies: (map['print_copies'] as int?) ?? 1,
      vatCategories: map['vat_categories'] as String? ?? '[]',
      smsEnabled: (map['sms_enabled'] as int?) == 1,
      smsProvider: map['sms_provider'] as String?,
      smsApiKey: map['sms_api_key'] as String?,
      smsTemplate: map['sms_template'] as String?,
      qrEnabled: (map['qr_enabled'] as int?) == 1,
      qrFormat: map['qr_format'] as String? ?? 'type|id|timestamp|customerId|amount|hash',
      debugMode: (map['debug_mode'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String? ?? DateTime.now().toIso8601String()),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    final map = {
      'business_name': businessName,
      'business_phone': businessPhone,
      'business_address': businessAddress,
      'business_tax_id': businessTaxId,
      'business_logo': businessLogo,
      'owner_name': ownerName,
      'business_email': businessEmail,
      'business_city': businessCity,
      'business_district': businessDistrict,
      'business_type': businessType,
      'currency': currency,

      'printer_name': printerName,
      'printer_ip': printerIp,
      'printer_port': printerPort,
      'paper_width': paperWidth,
      'print_receipt': printReceipt ? 1 : 0,
      'print_qr_code': printQRCode ? 1 : 0,
      'print_product_details': printProductDetails ? 1 : 0,
      'print_barcode': printBarcode ? 1 : 0,
      'print_copies': printCopies,
      'vat_categories': vatCategories,
      'sms_enabled': smsEnabled ? 1 : 0,
      'sms_provider': smsProvider,
      'sms_api_key': smsApiKey,
      'sms_template': smsTemplate,
      'qr_enabled': qrEnabled ? 1 : 0,
      'qr_format': qrFormat,
      'debug_mode': debugMode ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  Settings copyWith({
    int? id,
    String? businessName,
    String? businessPhone,
    String? businessAddress,
    String? businessTaxId,
    String? businessLogo,
    String? ownerName,
    String? businessEmail,
    String? businessCity,
    String? businessDistrict,
    String? businessType,
    String? currency,

    String? printerName,
    String? printerIp,
    int? printerPort,
    int? paperWidth,
    bool? printReceipt,
    bool? printQRCode,
    bool? printProductDetails,
    bool? printBarcode,
    int? printCopies,
    String? vatCategories,
    bool? smsEnabled,
    String? smsProvider,
    String? smsApiKey,
    String? smsTemplate,
    bool? qrEnabled,
    String? qrFormat,
    bool? debugMode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Settings(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      businessPhone: businessPhone ?? this.businessPhone,
      businessAddress: businessAddress ?? this.businessAddress,
      businessTaxId: businessTaxId ?? this.businessTaxId,
      businessLogo: businessLogo ?? this.businessLogo,
      ownerName: ownerName ?? this.ownerName,
      businessEmail: businessEmail ?? this.businessEmail,
      businessCity: businessCity ?? this.businessCity,
      businessDistrict: businessDistrict ?? this.businessDistrict,
      businessType: businessType ?? this.businessType,
      currency: currency ?? this.currency,

      printerName: printerName ?? this.printerName,
      printerIp: printerIp ?? this.printerIp,
      printerPort: printerPort ?? this.printerPort,
      paperWidth: paperWidth ?? this.paperWidth,
      printReceipt: printReceipt ?? this.printReceipt,
      printQRCode: printQRCode ?? this.printQRCode,
      printProductDetails: printProductDetails ?? this.printProductDetails,
      printBarcode: printBarcode ?? this.printBarcode,
      printCopies: printCopies ?? this.printCopies,
      vatCategories: vatCategories ?? this.vatCategories,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      smsProvider: smsProvider ?? this.smsProvider,
      smsApiKey: smsApiKey ?? this.smsApiKey,
      smsTemplate: smsTemplate ?? this.smsTemplate,
      qrEnabled: qrEnabled ?? this.qrEnabled,
      qrFormat: qrFormat ?? this.qrFormat,
      debugMode: debugMode ?? this.debugMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Settings($businessName)';
}

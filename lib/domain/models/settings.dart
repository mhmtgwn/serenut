// lib/domain/models/settings.dart
// Settings = Runtime configuration (Domain Model)

/// Sentinel value used to distinguish between "not provided" and explicitly null
/// in [Settings.copyWith] for nullable fields.
class _Unset {
  const _Unset();
}

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

  // Yeni eklenen ayarlar (Sprint 4)
  final bool soundNotificationEnabled;
  final bool smsAutoDebtReminderEnabled;
  final int smsAutoDebtReminderDays;
  final double smsAutoDebtReminderMinAmount;
  final bool labelPrinterEnabled;
  final String? labelPrinterIp;
  final int labelPrinterPort;
  final int labelPrinterCopies;
  final String? adminPinCode;

  // SMS SIM ve Limit Ayarları (Sprint 10)
  final int? smsSimSubscriptionId;
  final int? smsSimSlotIndex;
  final int? smsMonthlyLimit;
  final int smsSentThisMonth;
  final int? smsLimitResetMonth;

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
    // Sprint 4 defaults
    this.soundNotificationEnabled = false,
    this.smsAutoDebtReminderEnabled = false,
    this.smsAutoDebtReminderDays = 15,
    this.smsAutoDebtReminderMinAmount = 100.0,
    this.labelPrinterEnabled = false,
    this.labelPrinterIp,
    this.labelPrinterPort = 9100,
    this.labelPrinterCopies = 1,
    this.adminPinCode,
    this.smsSimSubscriptionId,
    this.smsSimSlotIndex,
    this.smsMonthlyLimit,
    this.smsSentThisMonth = 0,
    this.smsLimitResetMonth,
  }) : createdAt = createdAt ?? DateTime.now();

  // Validation
  bool get isValid => businessName.isNotEmpty && businessPhone.isNotEmpty;

  factory Settings.fromMap(Map<String, dynamic> map) {
    return Settings(
      id: map['id'] as int?,
      businessName: (map['business_name'] as String?) ?? (map['company_name'] as String?) ?? 'Serenut OS',
      businessPhone: (map['business_phone'] as String?) ?? (map['company_phone'] as String?) ?? '',
      businessAddress: (map['business_address'] as String?) ?? (map['company_address'] as String?) ?? '',
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

      // Sprint 4 mappings
      soundNotificationEnabled: (map['sound_notification_enabled'] as int?) == 1,
      smsAutoDebtReminderEnabled: (map['sms_auto_debt_reminder_enabled'] as int?) == 1,
      smsAutoDebtReminderDays: (map['sms_auto_debt_reminder_days'] as int?) ?? 15,
      smsAutoDebtReminderMinAmount: (map['sms_auto_debt_reminder_min_amount'] as num?)?.toDouble() ?? 100.0,
      labelPrinterEnabled: (map['label_printer_enabled'] as int?) == 1,
      labelPrinterIp: map['label_printer_ip'] as String?,
      labelPrinterPort: (map['label_printer_port'] as int?) ?? 9100,
      labelPrinterCopies: (map['label_printer_copies'] as int?) ?? 1,
      adminPinCode: map['admin_pin_code'] as String?,

      // Sprint 10 SIM SMS and Limits
      smsSimSubscriptionId: map['sms_sim_subscription_id'] as int?,
      smsSimSlotIndex: map['sms_sim_slot_index'] as int?,
      smsMonthlyLimit: map['sms_monthly_limit'] as int?,
      smsSentThisMonth: (map['sms_sent_this_month'] as int?) ?? 0,
      smsLimitResetMonth: map['sms_limit_reset_month'] as int?,
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

      // Sprint 4 serialization
      'sound_notification_enabled': soundNotificationEnabled ? 1 : 0,
      'sms_auto_debt_reminder_enabled': smsAutoDebtReminderEnabled ? 1 : 0,
      'sms_auto_debt_reminder_days': smsAutoDebtReminderDays,
      'sms_auto_debt_reminder_min_amount': smsAutoDebtReminderMinAmount,
      'label_printer_enabled': labelPrinterEnabled ? 1 : 0,
      'label_printer_ip': labelPrinterIp,
      'label_printer_port': labelPrinterPort,
      'label_printer_copies': labelPrinterCopies,
      'admin_pin_code': adminPinCode,
      'sms_sim_subscription_id': smsSimSubscriptionId,
      'sms_sim_slot_index': smsSimSlotIndex,
      'sms_monthly_limit': smsMonthlyLimit,
      'sms_sent_this_month': smsSentThisMonth,
      'sms_limit_reset_month': smsLimitResetMonth,
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

    // Sprint 4 copyWith parameters
    bool? soundNotificationEnabled,
    bool? smsAutoDebtReminderEnabled,
    int? smsAutoDebtReminderDays,
    double? smsAutoDebtReminderMinAmount,
    bool? labelPrinterEnabled,
    String? labelPrinterIp,
    int? labelPrinterPort,
    int? labelPrinterCopies,
    Object? adminPinCode = const _Unset(),
    int? smsSimSubscriptionId,
    int? smsSimSlotIndex,
    int? smsMonthlyLimit,
    int? smsSentThisMonth,
    int? smsLimitResetMonth,
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

      // Sprint 4 copyWith updates
      soundNotificationEnabled: soundNotificationEnabled ?? this.soundNotificationEnabled,
      smsAutoDebtReminderEnabled: smsAutoDebtReminderEnabled ?? this.smsAutoDebtReminderEnabled,
      smsAutoDebtReminderDays: smsAutoDebtReminderDays ?? this.smsAutoDebtReminderDays,
      smsAutoDebtReminderMinAmount: smsAutoDebtReminderMinAmount ?? this.smsAutoDebtReminderMinAmount,
      labelPrinterEnabled: labelPrinterEnabled ?? this.labelPrinterEnabled,
      labelPrinterIp: labelPrinterIp ?? this.labelPrinterIp,
      labelPrinterPort: labelPrinterPort ?? this.labelPrinterPort,
      labelPrinterCopies: labelPrinterCopies ?? this.labelPrinterCopies,
      adminPinCode: adminPinCode is _Unset ? this.adminPinCode : adminPinCode as String?,
      smsSimSubscriptionId: smsSimSubscriptionId ?? this.smsSimSubscriptionId,
      smsSimSlotIndex: smsSimSlotIndex ?? this.smsSimSlotIndex,
      smsMonthlyLimit: smsMonthlyLimit ?? this.smsMonthlyLimit,
      smsSentThisMonth: smsSentThisMonth ?? this.smsSentThisMonth,
      smsLimitResetMonth: smsLimitResetMonth ?? this.smsLimitResetMonth,
    );
  }

  @override
  String toString() => 'Settings($businessName)';
}

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
  final String currency; // ₺

  // Yazıcı ayarları
  final String? printerName;
  final String? printerIp;
  final int printerPort;
  final int paperWidth; // mm (80mm termal)
  final bool printReceipt;
  final bool printQRCode;
  final bool printProductDetails;
  final bool printBarcode;
  final int printCopies;
  final bool printLogo;
  final bool printCustomerBalance;
  final String receiptFont;
  final String receiptTextSize;
  final String receiptItemLayout;
  final String receiptFooterText;
  final int receiptFeedLines;
  final bool autoCutReceipt;
  final bool openCashDrawer;

  // KDV kategorileri (JSON string)
  final String vatCategories; // JSON: [{"name":"Normal","rate":18}, ...]

  // SMS ayarları
  final bool smsEnabled;
  final String? smsProvider; // 'sim'
  final String? smsApiKey;
  final String? smsTemplate;

  // QR Settings
  final bool qrEnabled;
  final String qrFormat; // 'type|id|timestamp|customerId|amount|hash'

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
  final String? labelPrinterName;
  final String? labelPrinterIp;
  final int labelPrinterPort;
  final int labelPrinterCopies;
  final String labelPrinterLanguage;
  final int labelWidthMm;
  final int labelHeightMm;
  final int labelGapMm;
  final int labelDpi;
  // Etiket Taslak Ayarları
  final bool labelShowBrand;
  final bool labelShowVat;
  final String labelFontSize;
  final bool labelOrderShowBusinessName;
  final bool labelOrderShowCustomerName;
  final bool labelOrderShowOrderNo;
  final bool labelOrderShowDate;
  final bool labelOrderShowTotalAmount;
  final bool labelOrderShowItemsCount;
  final String labelOrderFontSize;
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
    this.printLogo = true,
    this.printCustomerBalance = true,
    this.receiptFont = 'a',
    this.receiptTextSize = 'normal',
    this.receiptItemLayout = 'auto',
    this.receiptFooterText = 'Bizi tercih ettiğiniz için teşekkür ederiz!',
    this.receiptFeedLines = 2,
    this.autoCutReceipt = true,
    this.openCashDrawer = true,
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
    this.labelPrinterName,
    this.labelPrinterIp,
    this.labelPrinterPort = 9100,
    this.labelPrinterCopies = 1,
    this.labelPrinterLanguage = 'tspl',
    this.labelWidthMm = 50,
    this.labelHeightMm = 30,
    this.labelGapMm = 2,
    this.labelDpi = 203,
    this.labelShowBrand = true,
    this.labelShowVat = true,
    this.labelFontSize = 'Orta',
    this.labelOrderShowBusinessName = true,
    this.labelOrderShowCustomerName = true,
    this.labelOrderShowOrderNo = true,
    this.labelOrderShowDate = true,
    this.labelOrderShowTotalAmount = true,
    this.labelOrderShowItemsCount = true,
    this.labelOrderFontSize = 'Orta',
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
      businessName: (map['business_name'] as String?) ??
          (map['company_name'] as String?) ??
          'Serenut OS',
      businessPhone: (map['business_phone'] as String?) ??
          (map['company_phone'] as String?) ??
          '',
      businessAddress: (map['business_address'] as String?) ??
          (map['company_address'] as String?) ??
          '',
      businessTaxId:
          map['business_tax_id'] ?? map['company_tax_number'] as String?,
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
      printLogo: (map['print_logo'] as int? ?? 1) == 1,
      printCustomerBalance: (map['print_customer_balance'] as int? ?? 1) == 1,
      receiptFont: map['receipt_font'] as String? ?? 'a',
      receiptTextSize: map['receipt_text_size'] as String? ?? 'normal',
      receiptItemLayout: map['receipt_item_layout'] as String? ?? 'auto',
      receiptFooterText: map['receipt_footer_text'] as String? ??
          'Bizi tercih ettiğiniz için teşekkür ederiz!',
      receiptFeedLines: (map['receipt_feed_lines'] as int?) ?? 2,
      autoCutReceipt: (map['auto_cut_receipt'] as int? ?? 1) == 1,
      openCashDrawer: (map['open_cash_drawer'] as int? ?? 1) == 1,
      vatCategories: map['vat_categories'] as String? ?? '[]',
      smsEnabled: (map['sms_enabled'] as int?) == 1,
      smsProvider: map['sms_provider'] as String?,
      smsApiKey: map['sms_api_key'] as String?,
      smsTemplate: map['sms_template'] as String?,
      qrEnabled: (map['qr_enabled'] as int?) == 1,
      qrFormat: map['qr_format'] as String? ??
          'type|id|timestamp|customerId|amount|hash',
      debugMode: (map['debug_mode'] as int?) == 1,
      createdAt: DateTime.parse(
          map['created_at'] as String? ?? DateTime.now().toIso8601String()),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,

      // Sprint 4 mappings
      soundNotificationEnabled:
          (map['sound_notification_enabled'] as int?) == 1,
      smsAutoDebtReminderEnabled:
          (map['sms_auto_debt_reminder_enabled'] as int?) == 1,
      smsAutoDebtReminderDays:
          (map['sms_auto_debt_reminder_days'] as int?) ?? 15,
      smsAutoDebtReminderMinAmount:
          (map['sms_auto_debt_reminder_min_amount'] as num?)?.toDouble() ??
              100.0,
      labelPrinterEnabled: (map['label_printer_enabled'] as int?) == 1,
      labelPrinterName: map['label_printer_name'] as String?,
      labelPrinterIp: map['label_printer_ip'] as String?,
      labelPrinterPort: (map['label_printer_port'] as int?) ?? 9100,
      labelPrinterCopies: (map['label_printer_copies'] as int?) ?? 1,
      labelPrinterLanguage: map['label_printer_language'] as String? ?? 'tspl',
      labelWidthMm: (map['label_width_mm'] as int?) ?? 50,
      labelHeightMm: (map['label_height_mm'] as int?) ?? 30,
      labelGapMm: (map['label_gap_mm'] as int?) ?? 2,
      labelDpi: (map['label_dpi'] as int?) ?? 203,
      labelShowBrand: (map['label_show_brand'] as int? ?? 1) == 1,
      labelShowVat: (map['label_show_vat'] as int? ?? 1) == 1,
      labelFontSize: map['label_font_size'] as String? ?? 'Orta',
      labelOrderShowBusinessName: (map['label_order_show_business_name'] as int? ?? 1) == 1,
      labelOrderShowCustomerName: (map['label_order_show_customer_name'] as int? ?? 1) == 1,
      labelOrderShowOrderNo: (map['label_order_show_order_no'] as int? ?? 1) == 1,
      labelOrderShowDate: (map['label_order_show_date'] as int? ?? 1) == 1,
      labelOrderShowTotalAmount: (map['label_order_show_total_amount'] as int? ?? 1) == 1,
      labelOrderShowItemsCount: (map['label_order_show_items_count'] as int? ?? 1) == 1,
      labelOrderFontSize: map['label_order_font_size'] as String? ?? 'Orta',
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
      'print_logo': printLogo ? 1 : 0,
      'print_customer_balance': printCustomerBalance ? 1 : 0,
      'receipt_font': receiptFont,
      'receipt_text_size': receiptTextSize,
      'receipt_item_layout': receiptItemLayout,
      'receipt_footer_text': receiptFooterText,
      'receipt_feed_lines': receiptFeedLines,
      'auto_cut_receipt': autoCutReceipt ? 1 : 0,
      'open_cash_drawer': openCashDrawer ? 1 : 0,
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
      'label_printer_name': labelPrinterName,
      'label_printer_ip': labelPrinterIp,
      'label_printer_port': labelPrinterPort,
      'label_printer_copies': labelPrinterCopies,
      'label_printer_language': labelPrinterLanguage,
      'label_width_mm': labelWidthMm,
      'label_height_mm': labelHeightMm,
      'label_gap_mm': labelGapMm,
      'label_dpi': labelDpi,
      'label_show_brand': labelShowBrand ? 1 : 0,
      'label_show_vat': labelShowVat ? 1 : 0,
      'label_font_size': labelFontSize,
      'label_order_show_business_name': labelOrderShowBusinessName ? 1 : 0,
      'label_order_show_customer_name': labelOrderShowCustomerName ? 1 : 0,
      'label_order_show_order_no': labelOrderShowOrderNo ? 1 : 0,
      'label_order_show_date': labelOrderShowDate ? 1 : 0,
      'label_order_show_total_amount': labelOrderShowTotalAmount ? 1 : 0,
      'label_order_show_items_count': labelOrderShowItemsCount ? 1 : 0,
      'label_order_font_size': labelOrderFontSize,
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
    bool? printLogo,
    bool? printCustomerBalance,
    String? receiptFont,
    String? receiptTextSize,
    String? receiptItemLayout,
    String? receiptFooterText,
    int? receiptFeedLines,
    bool? autoCutReceipt,
    bool? openCashDrawer,
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
    String? labelPrinterName,
    String? labelPrinterIp,
    int? labelPrinterPort,
    int? labelPrinterCopies,
    String? labelPrinterLanguage,
    int? labelWidthMm,
    int? labelHeightMm,
    int? labelGapMm,
    int? labelDpi,
    bool? labelShowBrand,
    bool? labelShowVat,
    String? labelFontSize,
    bool? labelOrderShowBusinessName,
    bool? labelOrderShowCustomerName,
    bool? labelOrderShowOrderNo,
    bool? labelOrderShowDate,
    bool? labelOrderShowTotalAmount,
    bool? labelOrderShowItemsCount,
    String? labelOrderFontSize,
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
      printLogo: printLogo ?? this.printLogo,
      printCustomerBalance: printCustomerBalance ?? this.printCustomerBalance,
      receiptFont: receiptFont ?? this.receiptFont,
      receiptTextSize: receiptTextSize ?? this.receiptTextSize,
      receiptItemLayout: receiptItemLayout ?? this.receiptItemLayout,
      receiptFooterText: receiptFooterText ?? this.receiptFooterText,
      receiptFeedLines: receiptFeedLines ?? this.receiptFeedLines,
      autoCutReceipt: autoCutReceipt ?? this.autoCutReceipt,
      openCashDrawer: openCashDrawer ?? this.openCashDrawer,
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
      soundNotificationEnabled:
          soundNotificationEnabled ?? this.soundNotificationEnabled,
      smsAutoDebtReminderEnabled:
          smsAutoDebtReminderEnabled ?? this.smsAutoDebtReminderEnabled,
      smsAutoDebtReminderDays:
          smsAutoDebtReminderDays ?? this.smsAutoDebtReminderDays,
      smsAutoDebtReminderMinAmount:
          smsAutoDebtReminderMinAmount ?? this.smsAutoDebtReminderMinAmount,
      labelPrinterEnabled: labelPrinterEnabled ?? this.labelPrinterEnabled,
      labelPrinterName: labelPrinterName ?? this.labelPrinterName,
      labelPrinterIp: labelPrinterIp ?? this.labelPrinterIp,
      labelPrinterPort: labelPrinterPort ?? this.labelPrinterPort,
      labelPrinterCopies: labelPrinterCopies ?? this.labelPrinterCopies,
      labelPrinterLanguage: labelPrinterLanguage ?? this.labelPrinterLanguage,
      labelWidthMm: labelWidthMm ?? this.labelWidthMm,
      labelHeightMm: labelHeightMm ?? this.labelHeightMm,
      labelGapMm: labelGapMm ?? this.labelGapMm,
      labelDpi: labelDpi ?? this.labelDpi,
      labelShowBrand: labelShowBrand ?? this.labelShowBrand,
      labelShowVat: labelShowVat ?? this.labelShowVat,
      labelFontSize: labelFontSize ?? this.labelFontSize,
      labelOrderShowBusinessName:
          labelOrderShowBusinessName ?? this.labelOrderShowBusinessName,
      labelOrderShowCustomerName:
          labelOrderShowCustomerName ?? this.labelOrderShowCustomerName,
      labelOrderShowOrderNo:
          labelOrderShowOrderNo ?? this.labelOrderShowOrderNo,
      labelOrderShowDate: labelOrderShowDate ?? this.labelOrderShowDate,
      labelOrderShowTotalAmount:
          labelOrderShowTotalAmount ?? this.labelOrderShowTotalAmount,
      labelOrderShowItemsCount:
          labelOrderShowItemsCount ?? this.labelOrderShowItemsCount,
      labelOrderFontSize: labelOrderFontSize ?? this.labelOrderFontSize,
      adminPinCode:
          adminPinCode is _Unset ? this.adminPinCode : adminPinCode as String?,
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

/// Fiş şablonu modeli
class ReceiptTemplate {
  final String id;
  final String name;
  final String type; // 'order', 'payment', 'refund', 'daily_report'
  final ReceiptHeader header;
  final ReceiptBody body;
  final ReceiptFooter footer;
  final ReceiptSettings settings;

  ReceiptTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.header,
    required this.body,
    required this.footer,
    required this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'header': header.toMap(),
      'body': body.toMap(),
      'footer': footer.toMap(),
      'settings': settings.toMap(),
    };
  }

  factory ReceiptTemplate.fromMap(Map<String, dynamic> map) {
    return ReceiptTemplate(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? 'order',
      header: ReceiptHeader.fromMap(map['header'] ?? {}),
      body: ReceiptBody.fromMap(map['body'] ?? {}),
      footer: ReceiptFooter.fromMap(map['footer'] ?? {}),
      settings: ReceiptSettings.fromMap(map['settings'] ?? {}),
    );
  }

  /// Varsayılan sipariş fişi şablonu
  factory ReceiptTemplate.defaultOrder() {
    return ReceiptTemplate(
      id: 'default_order',
      name: 'Standart Sipariş Fişi',
      type: 'order',
      header: ReceiptHeader(
        showLogo: true,
        showCompanyName: true,
        showCompanyInfo: true,
        companyNameSize: 36,
        companyNameBold: true,
        companyInfoSize: 24,
      ),
      body: ReceiptBody(
        showOrderNumber: true,
        showCustomerInfo: true,
        showDateTime: true,
        showProducts: true,
        showPrices: true,
        showQuantity: true,
        showSubtotal: true,
        productNameSize: 24,
        productNameBold: true,
        priceSize: 24,
      ),
      footer: ReceiptFooter(
        showTotal: true,
        showPaymentMethod: true,
        showStatus: true,
        showNotes: true,
        showThankYou: true,
        showWebsite: true,
        totalSize: 36,
        totalBold: true,
        footerSize: 24,
      ),
      settings: ReceiptSettings(
        paperWidth: 58,
        fontSize: 24,
        lineSpacing: 1,
        marginTop: 0,
        marginBottom: 3,
        showSeparators: true,
        separatorChar: '-',
      ),
    );
  }

  /// Ödeme fişi şablonu
  factory ReceiptTemplate.payment() {
    return ReceiptTemplate(
      id: 'payment',
      name: 'Ödeme Fişi',
      type: 'payment',
      header: ReceiptHeader(
        showLogo: false,
        showCompanyName: true,
        showCompanyInfo: false,
        companyNameSize: 32,
        companyNameBold: true,
        companyInfoSize: 24,
      ),
      body: ReceiptBody(
        showOrderNumber: true,
        showCustomerInfo: true,
        showDateTime: true,
        showProducts: false,
        showPrices: true,
        showQuantity: false,
        showSubtotal: true,
        productNameSize: 24,
        productNameBold: false,
        priceSize: 28,
      ),
      footer: ReceiptFooter(
        showTotal: true,
        showPaymentMethod: true,
        showStatus: false,
        showNotes: false,
        showThankYou: true,
        showWebsite: false,
        totalSize: 40,
        totalBold: true,
        footerSize: 24,
      ),
      settings: ReceiptSettings(
        paperWidth: 58,
        fontSize: 24,
        lineSpacing: 1,
        marginTop: 0,
        marginBottom: 2,
        showSeparators: true,
        separatorChar: '=',
      ),
    );
  }
}

/// Fiş başlık ayarları
class ReceiptHeader {
  final bool showLogo;
  final bool showCompanyName;
  final bool showCompanyInfo;
  final int companyNameSize;
  final bool companyNameBold;
  final int companyInfoSize;

  ReceiptHeader({
    required this.showLogo,
    required this.showCompanyName,
    required this.showCompanyInfo,
    required this.companyNameSize,
    required this.companyNameBold,
    required this.companyInfoSize,
  });

  Map<String, dynamic> toMap() {
    return {
      'showLogo': showLogo,
      'showCompanyName': showCompanyName,
      'showCompanyInfo': showCompanyInfo,
      'companyNameSize': companyNameSize,
      'companyNameBold': companyNameBold,
      'companyInfoSize': companyInfoSize,
    };
  }

  factory ReceiptHeader.fromMap(Map<String, dynamic> map) {
    return ReceiptHeader(
      showLogo: map['showLogo'] ?? true,
      showCompanyName: map['showCompanyName'] ?? true,
      showCompanyInfo: map['showCompanyInfo'] ?? true,
      companyNameSize: map['companyNameSize'] ?? 36,
      companyNameBold: map['companyNameBold'] ?? true,
      companyInfoSize: map['companyInfoSize'] ?? 24,
    );
  }
}

/// Fiş gövde ayarları
class ReceiptBody {
  final bool showOrderNumber;
  final bool showCustomerInfo;
  final bool showDateTime;
  final bool showProducts;
  final bool showPrices;
  final bool showQuantity;
  final bool showSubtotal;
  final int productNameSize;
  final bool productNameBold;
  final int priceSize;

  ReceiptBody({
    required this.showOrderNumber,
    required this.showCustomerInfo,
    required this.showDateTime,
    required this.showProducts,
    required this.showPrices,
    required this.showQuantity,
    required this.showSubtotal,
    required this.productNameSize,
    required this.productNameBold,
    required this.priceSize,
  });

  Map<String, dynamic> toMap() {
    return {
      'showOrderNumber': showOrderNumber,
      'showCustomerInfo': showCustomerInfo,
      'showDateTime': showDateTime,
      'showProducts': showProducts,
      'showPrices': showPrices,
      'showQuantity': showQuantity,
      'showSubtotal': showSubtotal,
      'productNameSize': productNameSize,
      'productNameBold': productNameBold,
      'priceSize': priceSize,
    };
  }

  factory ReceiptBody.fromMap(Map<String, dynamic> map) {
    return ReceiptBody(
      showOrderNumber: map['showOrderNumber'] ?? true,
      showCustomerInfo: map['showCustomerInfo'] ?? true,
      showDateTime: map['showDateTime'] ?? true,
      showProducts: map['showProducts'] ?? true,
      showPrices: map['showPrices'] ?? true,
      showQuantity: map['showQuantity'] ?? true,
      showSubtotal: map['showSubtotal'] ?? true,
      productNameSize: map['productNameSize'] ?? 24,
      productNameBold: map['productNameBold'] ?? true,
      priceSize: map['priceSize'] ?? 24,
    );
  }
}

/// Fiş alt bilgi ayarları
class ReceiptFooter {
  final bool showTotal;
  final bool showPaymentMethod;
  final bool showStatus;
  final bool showNotes;
  final bool showThankYou;
  final bool showWebsite;
  final int totalSize;
  final bool totalBold;
  final int footerSize;

  ReceiptFooter({
    required this.showTotal,
    required this.showPaymentMethod,
    required this.showStatus,
    required this.showNotes,
    required this.showThankYou,
    required this.showWebsite,
    required this.totalSize,
    required this.totalBold,
    required this.footerSize,
  });

  Map<String, dynamic> toMap() {
    return {
      'showTotal': showTotal,
      'showPaymentMethod': showPaymentMethod,
      'showStatus': showStatus,
      'showNotes': showNotes,
      'showThankYou': showThankYou,
      'showWebsite': showWebsite,
      'totalSize': totalSize,
      'totalBold': totalBold,
      'footerSize': footerSize,
    };
  }

  factory ReceiptFooter.fromMap(Map<String, dynamic> map) {
    return ReceiptFooter(
      showTotal: map['showTotal'] ?? true,
      showPaymentMethod: map['showPaymentMethod'] ?? true,
      showStatus: map['showStatus'] ?? true,
      showNotes: map['showNotes'] ?? true,
      showThankYou: map['showThankYou'] ?? true,
      showWebsite: map['showWebsite'] ?? true,
      totalSize: map['totalSize'] ?? 36,
      totalBold: map['totalBold'] ?? true,
      footerSize: map['footerSize'] ?? 24,
    );
  }
}

/// Fiş genel ayarları
class ReceiptSettings {
  final int paperWidth; // 58mm veya 80mm
  final int fontSize;
  final int lineSpacing;
  final int marginTop;
  final int marginBottom;
  final bool showSeparators;
  final String separatorChar;

  ReceiptSettings({
    required this.paperWidth,
    required this.fontSize,
    required this.lineSpacing,
    required this.marginTop,
    required this.marginBottom,
    required this.showSeparators,
    required this.separatorChar,
  });

  Map<String, dynamic> toMap() {
    return {
      'paperWidth': paperWidth,
      'fontSize': fontSize,
      'lineSpacing': lineSpacing,
      'marginTop': marginTop,
      'marginBottom': marginBottom,
      'showSeparators': showSeparators,
      'separatorChar': separatorChar,
    };
  }

  factory ReceiptSettings.fromMap(Map<String, dynamic> map) {
    return ReceiptSettings(
      paperWidth: map['paperWidth'] ?? 58,
      fontSize: map['fontSize'] ?? 24,
      lineSpacing: map['lineSpacing'] ?? 1,
      marginTop: map['marginTop'] ?? 0,
      marginBottom: map['marginBottom'] ?? 3,
      showSeparators: map['showSeparators'] ?? true,
      separatorChar: map['separatorChar'] ?? '-',
    );
  }
}

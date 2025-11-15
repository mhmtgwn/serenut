/// Etiket şablonu modeli
class LabelTemplate {
  final String id;
  final String name;
  final String type; // 'product', 'price', 'barcode', 'shipping'
  final LabelSize size;
  final LabelContent content;
  final LabelStyle style;
  final LabelSettings settings;

  LabelTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.content,
    required this.style,
    required this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'size': size.toMap(),
      'content': content.toMap(),
      'style': style.toMap(),
      'settings': settings.toMap(),
    };
  }

  factory LabelTemplate.fromMap(Map<String, dynamic> map) {
    return LabelTemplate(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? 'product',
      size: LabelSize.fromMap(map['size'] ?? {}),
      content: LabelContent.fromMap(map['content'] ?? {}),
      style: LabelStyle.fromMap(map['style'] ?? {}),
      settings: LabelSettings.fromMap(map['settings'] ?? {}),
    );
  }

  /// Varsayılan ürün etiketi
  factory LabelTemplate.defaultProduct() {
    return LabelTemplate(
      id: 'default_product',
      name: 'Standart Ürün Etiketi',
      type: 'product',
      size: LabelSize(
        width: 40, // mm
        height: 30, // mm
        paperWidth: 60,
      ),
      content: LabelContent(
        showProductName: true,
        showPrice: true,
        showBarcode: true,
        showSKU: true,
        showCompanyName: true,
        showDate: false,
        showCategory: false,
      ),
      style: LabelStyle(
        productNameSize: 28,
        productNameBold: true,
        priceSize: 36,
        priceBold: true,
        barcodeHeight: 60,
        showBarcodeText: true,
        border: true,
        borderWidth: 2,
      ),
      settings: LabelSettings(
        orientation: 'portrait',
        alignment: 'center',
        marginTop: 2,
        marginBottom: 2,
        marginLeft: 2,
        marginRight: 2,
      ),
    );
  }

  /// Fiyat etiketi
  factory LabelTemplate.price() {
    return LabelTemplate(
      id: 'price_label',
      name: 'Fiyat Etiketi',
      type: 'price',
      size: LabelSize(
        width: 30,
        height: 20,
        paperWidth: 60,
      ),
      content: LabelContent(
        showProductName: true,
        showPrice: true,
        showBarcode: false,
        showSKU: false,
        showCompanyName: false,
        showDate: false,
        showCategory: false,
      ),
      style: LabelStyle(
        productNameSize: 24,
        productNameBold: false,
        priceSize: 40,
        priceBold: true,
        barcodeHeight: 0,
        showBarcodeText: false,
        border: true,
        borderWidth: 1,
      ),
      settings: LabelSettings(
        orientation: 'landscape',
        alignment: 'center',
        marginTop: 1,
        marginBottom: 1,
        marginLeft: 1,
        marginRight: 1,
      ),
    );
  }

  /// Barkod etiketi
  factory LabelTemplate.barcode() {
    return LabelTemplate(
      id: 'barcode_label',
      name: 'Barkod Etiketi',
      type: 'barcode',
      size: LabelSize(
        width: 50,
        height: 25,
        paperWidth: 60,
      ),
      content: LabelContent(
        showProductName: false,
        showPrice: false,
        showBarcode: true,
        showSKU: true,
        showCompanyName: false,
        showDate: false,
        showCategory: false,
      ),
      style: LabelStyle(
        productNameSize: 20,
        productNameBold: false,
        priceSize: 24,
        priceBold: false,
        barcodeHeight: 80,
        showBarcodeText: true,
        border: false,
        borderWidth: 0,
      ),
      settings: LabelSettings(
        orientation: 'landscape',
        alignment: 'center',
        marginTop: 2,
        marginBottom: 2,
        marginLeft: 2,
        marginRight: 2,
      ),
    );
  }

  /// Kargo etiketi
  factory LabelTemplate.shipping() {
    return LabelTemplate(
      id: 'shipping_label',
      name: 'Kargo Etiketi',
      type: 'shipping',
      size: LabelSize(
        width: 100,
        height: 150,
        paperWidth: 100,
      ),
      content: LabelContent(
        showProductName: true,
        showPrice: false,
        showBarcode: true,
        showSKU: true,
        showCompanyName: true,
        showDate: true,
        showCategory: true,
      ),
      style: LabelStyle(
        productNameSize: 32,
        productNameBold: true,
        priceSize: 28,
        priceBold: false,
        barcodeHeight: 100,
        showBarcodeText: true,
        border: true,
        borderWidth: 3,
      ),
      settings: LabelSettings(
        orientation: 'portrait',
        alignment: 'left',
        marginTop: 5,
        marginBottom: 5,
        marginLeft: 5,
        marginRight: 5,
      ),
    );
  }
}

/// Etiket boyutu
class LabelSize {
  final int width; // mm
  final int height; // mm
  final int paperWidth; // mm

  LabelSize({
    required this.width,
    required this.height,
    required this.paperWidth,
  });

  Map<String, dynamic> toMap() {
    return {
      'width': width,
      'height': height,
      'paperWidth': paperWidth,
    };
  }

  factory LabelSize.fromMap(Map<String, dynamic> map) {
    return LabelSize(
      width: map['width'] ?? 40,
      height: map['height'] ?? 30,
      paperWidth: map['paperWidth'] ?? 60,
    );
  }
}

/// Etiket içeriği
class LabelContent {
  final bool showProductName;
  final bool showPrice;
  final bool showBarcode;
  final bool showSKU;
  final bool showCompanyName;
  final bool showDate;
  final bool showCategory;

  LabelContent({
    required this.showProductName,
    required this.showPrice,
    required this.showBarcode,
    required this.showSKU,
    required this.showCompanyName,
    required this.showDate,
    required this.showCategory,
  });

  Map<String, dynamic> toMap() {
    return {
      'showProductName': showProductName,
      'showPrice': showPrice,
      'showBarcode': showBarcode,
      'showSKU': showSKU,
      'showCompanyName': showCompanyName,
      'showDate': showDate,
      'showCategory': showCategory,
    };
  }

  factory LabelContent.fromMap(Map<String, dynamic> map) {
    return LabelContent(
      showProductName: map['showProductName'] ?? true,
      showPrice: map['showPrice'] ?? true,
      showBarcode: map['showBarcode'] ?? true,
      showSKU: map['showSKU'] ?? true,
      showCompanyName: map['showCompanyName'] ?? true,
      showDate: map['showDate'] ?? false,
      showCategory: map['showCategory'] ?? false,
    );
  }
}

/// Etiket stili
class LabelStyle {
  final int productNameSize;
  final bool productNameBold;
  final int priceSize;
  final bool priceBold;
  final int barcodeHeight;
  final bool showBarcodeText;
  final bool border;
  final int borderWidth;

  LabelStyle({
    required this.productNameSize,
    required this.productNameBold,
    required this.priceSize,
    required this.priceBold,
    required this.barcodeHeight,
    required this.showBarcodeText,
    required this.border,
    required this.borderWidth,
  });

  Map<String, dynamic> toMap() {
    return {
      'productNameSize': productNameSize,
      'productNameBold': productNameBold,
      'priceSize': priceSize,
      'priceBold': priceBold,
      'barcodeHeight': barcodeHeight,
      'showBarcodeText': showBarcodeText,
      'border': border,
      'borderWidth': borderWidth,
    };
  }

  factory LabelStyle.fromMap(Map<String, dynamic> map) {
    return LabelStyle(
      productNameSize: map['productNameSize'] ?? 28,
      productNameBold: map['productNameBold'] ?? true,
      priceSize: map['priceSize'] ?? 36,
      priceBold: map['priceBold'] ?? true,
      barcodeHeight: map['barcodeHeight'] ?? 60,
      showBarcodeText: map['showBarcodeText'] ?? true,
      border: map['border'] ?? true,
      borderWidth: map['borderWidth'] ?? 2,
    );
  }
}

/// Etiket ayarları
class LabelSettings {
  final String orientation; // 'portrait', 'landscape'
  final String alignment; // 'left', 'center', 'right'
  final int marginTop;
  final int marginBottom;
  final int marginLeft;
  final int marginRight;

  LabelSettings({
    required this.orientation,
    required this.alignment,
    required this.marginTop,
    required this.marginBottom,
    required this.marginLeft,
    required this.marginRight,
  });

  Map<String, dynamic> toMap() {
    return {
      'orientation': orientation,
      'alignment': alignment,
      'marginTop': marginTop,
      'marginBottom': marginBottom,
      'marginLeft': marginLeft,
      'marginRight': marginRight,
    };
  }

  factory LabelSettings.fromMap(Map<String, dynamic> map) {
    return LabelSettings(
      orientation: map['orientation'] ?? 'portrait',
      alignment: map['alignment'] ?? 'center',
      marginTop: map['marginTop'] ?? 2,
      marginBottom: map['marginBottom'] ?? 2,
      marginLeft: map['marginLeft'] ?? 2,
      marginRight: map['marginRight'] ?? 2,
    );
  }
}

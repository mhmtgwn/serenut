// lib/domain/models/shared_models.dart
// Unified domain models shared between Data Pipeline (Python) and POS App (Dart)
// Revized: 24 Jun 2026

class SharedProduct {
  final String barcode;
  final String name;
  final String category;
  final String? brand;
  final String? imageUrl;
  final String? description;
  final double vatRate;

  SharedProduct({
    required this.barcode,
    required this.name,
    required this.category,
    this.brand,
    this.imageUrl,
    this.description,
    this.vatRate = 18.0,
  });

  Map<String, dynamic> toMap() => {
        'barcode': barcode,
        'name': name,
        'category': category,
        'brand': brand,
        'image_url': imageUrl,
        'description': description,
        'vat_rate': vatRate,
      };

  factory SharedProduct.fromMap(Map<String, dynamic> map) => SharedProduct(
        barcode: map['barcode'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        brand: map['brand'] as String?,
        imageUrl: map['image_url'] as String?,
        description: map['description'] as String?,
        vatRate: (map['vat_rate'] as num?)?.toDouble() ?? 18.0,
      );

  bool get isValid =>
      barcode.trim().length >= 5 &&
      name.trim().isNotEmpty &&
      category.trim().isNotEmpty;
}

class SharedPrice {
  final String barcode;
  final String marketName;
  final double price;
  final String currency;
  final String? dateScraped;

  SharedPrice({
    required this.barcode,
    required this.marketName,
    required this.price,
    this.currency = 'TRY',
    this.dateScraped,
  });

  Map<String, dynamic> toMap() => {
        'barcode': barcode,
        'market_name': marketName,
        'price': price,
        'currency': currency,
        'date_scraped': dateScraped,
      };

  factory SharedPrice.fromMap(Map<String, dynamic> map) => SharedPrice(
        barcode: map['barcode'] as String,
        marketName: map['market_name'] as String,
        price: (map['price'] as num).toDouble(),
        currency: map['currency'] as String? ?? 'TRY',
        dateScraped: map['date_scraped'] as String?,
      );

  bool get isValid =>
      barcode.trim().length >= 5 && marketName.trim().isNotEmpty && price > 0;
}

class SharedCategory {
  final String name;
  final double vatRate;
  final String? description;

  SharedCategory({
    required this.name,
    this.vatRate = 18.0,
    this.description,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'vat_rate': vatRate,
        'description': description,
      };

  factory SharedCategory.fromMap(Map<String, dynamic> map) => SharedCategory(
        name: map['name'] as String,
        vatRate: (map['vat_rate'] as num?)?.toDouble() ?? 18.0,
        description: map['description'] as String?,
      );

  bool get isValid => name.trim().isNotEmpty && vatRate >= 0 && vatRate <= 100;
}

class SharedMarket {
  final String name;
  final String? logoUrl;

  SharedMarket({
    required this.name,
    this.logoUrl,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'logo_url': logoUrl,
      };

  factory SharedMarket.fromMap(Map<String, dynamic> map) => SharedMarket(
        name: map['name'] as String,
        logoUrl: map['logo_url'] as String?,
      );

  bool get isValid => name.trim().isNotEmpty;
}

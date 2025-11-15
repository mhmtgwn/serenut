class Product {
  final int id;
  final String? barcode;
  final String name;
  final double price;
  final double purchasePrice;
  final double tax;
  final double discount;
  final double stock;
  final double criticalStock;
  final String unit;
  final String? description;
  final String? imagePath;
  final String? category;
  final String? brand;
  final double profitMargin;
  final double finalPrice;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    this.barcode,
    required this.name,
    required this.price,
    this.purchasePrice = 0,
    this.tax = 0,
    this.discount = 0,
    required this.stock,
    this.criticalStock = 0,
    required this.unit,
    this.description,
    this.imagePath,
    this.category,
    this.brand,
    this.profitMargin = 0,
    this.finalPrice = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      barcode: map['barcode'],
      name: map['name'],
      price: (map['price'] as num).toDouble(),
      purchasePrice: (map['purchasePrice'] as num?)?.toDouble() ?? 0,
      tax: (map['tax'] as num?)?.toDouble() ?? 0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0,
      stock: (map['stock'] as num).toDouble(),
      criticalStock: (map['criticalStock'] as num?)?.toDouble() ?? 0,
      unit: map['unit'],
      description: map['description'],
      imagePath: map['imagePath'],
      category: map['category'],
      brand: map['brand'],
      profitMargin: (map['profitMargin'] as num?)?.toDouble() ?? 0,
      finalPrice: (map['finalPrice'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'price': price,
      'purchasePrice': purchasePrice,
      'tax': tax,
      'discount': discount,
      'stock': stock,
      'criticalStock': criticalStock,
      'unit': unit,
      'description': description,
      'imagePath': imagePath,
      'category': category,
      'brand': brand,
      'profitMargin': profitMargin,
      'finalPrice': finalPrice,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    double? price,
    double? purchasePrice,
    double? tax,
    double? discount,
    double? stock,
    double? criticalStock,
    String? unit,
    String? description,
    String? imagePath,
    String? category,
    String? brand,
    double? profitMargin,
    double? finalPrice,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      tax: tax ?? this.tax,
      discount: discount ?? this.discount,
      stock: stock ?? this.stock,
      criticalStock: criticalStock ?? this.criticalStock,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      imagePath: imagePath ?? this.imagePath,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      profitMargin: profitMargin ?? this.profitMargin,
      finalPrice: finalPrice ?? this.finalPrice,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Geriye dönük uyumluluk için
  String? get imageUrl => imagePath;
} 

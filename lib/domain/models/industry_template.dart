// lib/domain/models/industry_template.dart
// Product Catalog Seed Templates for Market, Kafe, and Kuruyemişçi

class TemplateProduct {
  final String name;
  final String? barcode;
  final double price;
  final double vatRate; // e.g. 1.0, 10.0, 20.0 (Turkish VAT standard)
  final String category;
  final bool isByWeight;

  const TemplateProduct({
    required this.name,
    this.barcode,
    required this.price,
    required this.vatRate,
    required this.category,
    this.isByWeight = false,
  });
}

class IndustryTemplate {
  final String name; // 'Market' | 'Kafe' | 'Kuruyemişçi'
  final List<String> categories;
  final List<TemplateProduct> products;

  const IndustryTemplate({
    required this.name,
    required this.categories,
    required this.products,
  });
}

class IndustryTemplateRegistry {
  static const List<IndustryTemplate> templates = [
    IndustryTemplate(
      name: 'Market',
      categories: ['Temel Gıda', 'Atıştırmalık', 'Temizlik', 'İçecekler'],
      products: [
        TemplateProduct(name: 'Ekmek 250g', barcode: '8690001001001', price: 10.0, vatRate: 1.0, category: 'Temel Gıda'),
        TemplateProduct(name: 'Yarım Yağlı Süt 1L', barcode: '8690002002002', price: 35.0, vatRate: 10.0, category: 'Temel Gıda'),
        TemplateProduct(name: 'Makarna 500g', barcode: '8690003003003', price: 15.0, vatRate: 1.0, category: 'Temel Gıda'),
        TemplateProduct(name: 'Çikolatalı Gofret', barcode: '8690004004004', price: 8.0, vatRate: 10.0, category: 'Atıştırmalık'),
        TemplateProduct(name: 'Sıvı Bulaşık Deterjanı 1L', barcode: '8690005005005', price: 65.0, vatRate: 20.0, category: 'Temizlik'),
        TemplateProduct(name: 'Kola 330ml', barcode: '8690006006006', price: 30.0, vatRate: 10.0, category: 'İçecekler'),
        TemplateProduct(name: 'Maden Suyu 200ml', barcode: '8690007007007', price: 10.0, vatRate: 10.0, category: 'İçecekler'),
      ],
    ),
    IndustryTemplate(
      name: 'Kafe',
      categories: ['Sıcak İçecekler', 'Soğuk İçecekler', 'Tatlılar', 'Kahvaltılık'],
      products: [
        TemplateProduct(name: 'Türk Kahvesi', price: 50.0, vatRate: 10.0, category: 'Sıcak İçecekler'),
        TemplateProduct(name: 'Çay (Cam Bardak)', price: 20.0, vatRate: 10.0, category: 'Sıcak İçecekler'),
        TemplateProduct(name: 'Caffe Latte', price: 75.0, vatRate: 10.0, category: 'Sıcak İçecekler'),
        TemplateProduct(name: 'Limonata (Ev Yapımı)', price: 60.0, vatRate: 10.0, category: 'Soğuk İçecekler'),
        TemplateProduct(name: 'San Sebastian Cheesecake', price: 120.0, vatRate: 10.0, category: 'Tatlılar'),
        TemplateProduct(name: 'Tiramisu', price: 110.0, vatRate: 10.0, category: 'Tatlılar'),
        TemplateProduct(name: 'Tost (Karışık)', price: 85.0, vatRate: 10.0, category: 'Kahvaltılık'),
      ],
    ),
    IndustryTemplate(
      name: 'Kuruyemişçi',
      categories: ['Kuruyemiş', 'Kuru Meyve', 'Lüks Karışım', 'Şekerleme'],
      products: [
        TemplateProduct(name: 'Tuzlu Fıstık (Kg)', barcode: '8691001001', price: 180.0, vatRate: 1.0, category: 'Kuruyemiş', isByWeight: true),
        TemplateProduct(name: 'Kaju Fıstığı (Kg)', barcode: '8691002002', price: 420.0, vatRate: 1.0, category: 'Kuruyemiş', isByWeight: true),
        TemplateProduct(name: 'Çiğ Badem (Kg)', barcode: '8691003003', price: 380.0, vatRate: 1.0, category: 'Kuruyemiş', isByWeight: true),
        TemplateProduct(name: 'Kuru Kayısı (Kg)', barcode: '8691004004', price: 250.0, vatRate: 1.0, category: 'Kuru Meyve', isByWeight: true),
        TemplateProduct(name: 'Lüks Kokteyl Kuruyemiş (Kg)', barcode: '8691005005', price: 350.0, vatRate: 1.0, category: 'Lüks Karışım', isByWeight: true),
        TemplateProduct(name: 'Yumuşak Şeker (Kg)', barcode: '8691006006', price: 150.0, vatRate: 10.0, category: 'Şekerleme', isByWeight: true),
      ],
    ),
  ];

  static IndustryTemplate? getTemplate(String name) {
    try {
      return templates.firstWhere((t) => t.name.toLowerCase() == name.toLowerCase());
    } catch (_) {
      return null;
    }
  }
}

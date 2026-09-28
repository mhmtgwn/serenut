// lib/domain/models/industry_template.dart
// Product Catalog Seed Templates for Fındıkçı, Market, Kafe, and Kuruyemişçi

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
  final String name; // 'Fındıkçı' | 'Market' | 'Kafe' | 'Kuruyemişçi'
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
      name: 'Fındıkçı',
      categories: ['Hizmet', 'Şekerleme & Ezme', 'Kremalar', 'Butik & Kurabiye'],
      products: [
        TemplateProduct(
            name: 'Kırma',
            price: 40.0,
            vatRate: 20.0,
            category: 'Hizmet'),
        TemplateProduct(
            name: 'Kır 1Kg Pk.',
            price: 45.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'KIR 0.5 PK',
            price: 55.0,
            vatRate: 20.0,
            category: 'Hizmet'),
        TemplateProduct(
            name: 'Kavurma',
            price: 70.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'kavurma 1kg pk',
            price: 70.0,
            vatRate: 20.0,
            category: 'Hizmet'),
        TemplateProduct(
            name: 'Kır Kavur',
            price: 65.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'Kır Kavur 1Kg Pk.',
            price: 70.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'Kır Kavur 0.5 Pk.',
            price: 80.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'Kır Kavur 0.25 Pk.',
            price: 90.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'Ezme Kabuklu',
            price: 130.0,
            vatRate: 20.0,
            category: 'Hizmet',
            isByWeight: true),
        TemplateProduct(
            name: 'Ezme Kavanoz',
            price: 70.0,
            vatRate: 20.0,
            category: 'Hizmet'),
        TemplateProduct(
            name: 'Paket',
            price: 20.0,
            vatRate: 20.0,
            category: 'Hizmet'),
        TemplateProduct(
            name: 'FINDIK 500 GR',
            price: 500.0,
            vatRate: 1.0,
            category: 'Şekerleme & Ezme'),
        TemplateProduct(
            name: 'FINDIK EZMESİ 350GR',
            price: 300.0,
            vatRate: 1.0,
            category: 'Şekerleme & Ezme'),
        TemplateProduct(
            name: 'Süt\'lü Fındık Kreması',
            price: 250.0,
            vatRate: 1.0,
            category: 'Kremalar'),
        TemplateProduct(
            name: 'Süt\'lü Fındık Kreması %23',
            price: 200.0,
            vatRate: 1.0,
            category: 'Kremalar'),
        TemplateProduct(
            name: 'Süt\'lü Fındık Kreması %45',
            price: 250.0,
            vatRate: 1.0,
            category: 'Kremalar'),
        TemplateProduct(
            name: 'Kakao\'lu Fındık Kreması',
            price: 250.0,
            vatRate: 1.0,
            category: 'Kremalar'),
        TemplateProduct(
            name: 'Kakao\'lu Fındık Kreması %23',
            price: 200.0,
            vatRate: 1.0,
            category: 'Kremalar'),
        TemplateProduct(
            name: 'Kakao\'lu Fındık Kreması %45',
            price: 250.0,
            vatRate: 1.0,
            category: 'Kremalar'),
        TemplateProduct(
            name: 'Saklı Bahçe',
            price: 250.0,
            vatRate: 10.0,
            category: 'Butik & Kurabiye'),
        TemplateProduct(
            name: 'Çikolatalı Krokan',
            price: 200.0,
            vatRate: 10.0,
            category: 'Butik & Kurabiye'),
        TemplateProduct(
            name: 'Armonia Japon Kurabiyesi',
            price: 200.0,
            vatRate: 10.0,
            category: 'Butik & Kurabiye'),
      ],
    ),
    IndustryTemplate(
      name: 'Market',
      categories: ['Temel Gıda', 'Atıştırmalık', 'Temizlik', 'İçecekler'],
      products: [
        TemplateProduct(
            name: 'Ekmek 250g',
            barcode: '8690001001001',
            price: 10.0,
            vatRate: 1.0,
            category: 'Temel Gıda'),
        TemplateProduct(
            name: 'Yarım Yağlı Süt 1L',
            barcode: '8690002002002',
            price: 35.0,
            vatRate: 10.0,
            category: 'Temel Gıda'),
        TemplateProduct(
            name: 'Makarna 500g',
            barcode: '8690003003003',
            price: 15.0,
            vatRate: 1.0,
            category: 'Temel Gıda'),
        TemplateProduct(
            name: 'Çikolatalı Gofret',
            barcode: '8690004004004',
            price: 12.0,
            vatRate: 10.0,
            category: 'Atıştırmalık'),
        TemplateProduct(
            name: 'Çamaşır Deterjanı 1.5kg',
            barcode: '8690005005005',
            price: 95.0,
            vatRate: 20.0,
            category: 'Temizlik'),
        TemplateProduct(
            name: 'Maden Suyu 200ml',
            barcode: '8690006006006',
            price: 8.0,
            vatRate: 10.0,
            category: 'İçecekler'),
        TemplateProduct(
            name: 'Siyah Çay 1kg',
            barcode: '8690007007007',
            price: 120.0,
            vatRate: 1.0,
            category: 'Temel Gıda'),
      ],
    ),
    IndustryTemplate(
      name: 'Kafe',
      categories: ['Sıcak İçecekler', 'Soğuk İçecekler', 'Tatlılar', 'Yiyecekler'],
      products: [
        TemplateProduct(
            name: 'Türk Kahvesi',
            price: 45.0,
            vatRate: 10.0,
            category: 'Sıcak İçecekler'),
        TemplateProduct(
            name: 'Filtre Kahve',
            price: 60.0,
            vatRate: 10.0,
            category: 'Sıcak İçecekler'),
        TemplateProduct(
            name: 'Latte',
            price: 75.0,
            vatRate: 10.0,
            category: 'Sıcak İçecekler'),
        TemplateProduct(
            name: 'Çay',
            price: 20.0,
            vatRate: 10.0,
            category: 'Sıcak İçecekler'),
        TemplateProduct(
            name: 'Limonata',
            price: 55.0,
            vatRate: 10.0,
            category: 'Soğuk İçecekler'),
        TemplateProduct(
            name: 'San Sebastian Cheesecake',
            price: 130.0,
            vatRate: 10.0,
            category: 'Tatlılar'),
        TemplateProduct(
            name: 'Tost (Kaşarlı)',
            price: 70.0,
            vatRate: 10.0,
            category: 'Yiyecekler'),
      ],
    ),
    IndustryTemplate(
      name: 'Kuruyemişçi',
      categories: [
        'Kavrulmuş Kuruyemiş',
        'Çiğ Kuruyemiş',
        'Kuru Meyve',
        'Lüks Karışım',
        'Şekerleme'
      ],
      products: [
        TemplateProduct(
            name: 'Kavrulmuş Fındık (Kg)',
            barcode: '8691001001',
            price: 280.0,
            vatRate: 1.0,
            category: 'Kavrulmuş Kuruyemiş',
            isByWeight: true),
        TemplateProduct(
            name: 'Antep Fıstığı (Kg)',
            barcode: '8691002002',
            price: 450.0,
            vatRate: 1.0,
            category: 'Kavrulmuş Kuruyemiş',
            isByWeight: true),
        TemplateProduct(
            name: 'Çiğ Badem (Kg)',
            barcode: '8691003003',
            price: 320.0,
            vatRate: 1.0,
            category: 'Çiğ Kuruyemiş',
            isByWeight: true),
        TemplateProduct(
            name: 'Kuru İncir (Kg)',
            barcode: '8691004004',
            price: 220.0,
            vatRate: 1.0,
            category: 'Kuru Meyve',
            isByWeight: true),
        TemplateProduct(
            name: 'Lüks Kokteyl Kuruyemiş (Kg)',
            barcode: '8691005005',
            price: 350.0,
            vatRate: 1.0,
            category: 'Lüks Karışım',
            isByWeight: true),
        TemplateProduct(
            name: 'Yumuşak Şeker (Kg)',
            barcode: '8691006006',
            price: 150.0,
            vatRate: 10.0,
            category: 'Şekerleme',
            isByWeight: true),
      ],
    ),
  ];

  static IndustryTemplate? getTemplate(String name) {
    try {
      final clean = name.toLowerCase().trim();
      return templates.firstWhere(
        (t) =>
            t.name.toLowerCase() == clean ||
            (clean.contains('fındık') && t.name == 'Fındıkçı') ||
            (clean.contains('kuruyemiş') && t.name == 'Kuruyemişçi'),
      );
    } catch (_) {
      return templates.first;
    }
  }
}

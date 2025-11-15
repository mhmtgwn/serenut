import 'package:flutter/material.dart';

class ReceiptLivePreview extends StatefulWidget {
  final double paperWidth;
  final double paperHeight;
  final double margin;
  final String fontFamily;
  final double fontSize;
  final List<String> contentOrder;
  final Map<String, bool> contentVisibility;
  final String designType; // 'receipt', 'product_label', 'shelf_label', 'order_label'

  const ReceiptLivePreview({
    Key? key,
    required this.paperWidth,
    required this.paperHeight,
    required this.margin,
    required this.fontFamily,
    required this.fontSize,
    required this.contentOrder,
    required this.contentVisibility,
    this.designType = 'receipt',
  }) : super(key: key);

  @override
  State<ReceiptLivePreview> createState() => _ReceiptLivePreviewState();
}

class _ReceiptLivePreviewState extends State<ReceiptLivePreview> {
  // Ölçeklendirme faktörü
  double _scale = 1.0;
  
  // İçerik başlıkları
  final Map<String, String> _contentTitles = {
    'logo': 'Logo',
    'businessName': 'İşletme Adı',
    'address': 'Adres',
    'phone': 'Telefon',
    'taxInfo': 'Vergi Bilgileri',
    'receiptNo': 'Fiş No',
    'date': 'Tarih',
    'items': 'Ürünler',
    'subtotal': 'Ara Toplam',
    'tax': 'KDV',
    'total': 'Toplam',
    'paymentMethod': 'Ödeme Yöntemi',
    'barcode': 'Barkod',
    'footer': 'Alt Bilgi',
  };
  
  // Sample products for preview
  final List<Map<String, dynamic>> _sampleItems = [
    {'name': 'Ürün 1', 'quantity': 2, 'price': 10.50},
    {'name': 'Ürün 2', 'quantity': 1, 'price': 25.00},
    {'name': 'Ürün 3', 'quantity': 3, 'price': 5.75},
  ];

  @override
  void initState() {
    super.initState();
    _scale = 2.0; // Başlangıç ölçeği
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kontrol paneli
        _buildControlPanel(),
        
        const SizedBox(height: 16),
        
        // Önizleme alanı - doğrudan fiş önizlemesi
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: widget.paperWidth * _scale,
                  height: _calculateTotalHeight() * _scale,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(26),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(3, 3),
                      ),
                    ],
                  ),
                  child: _buildAutoLayoutContent(),
                ),
              ),
            ),
          ),
        ),
        
        // Gerçek boyut bilgisi
        Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.straighten, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Gerçek Boyut: ${widget.paperWidth.toStringAsFixed(1)} x ${_calculateTotalHeight().toStringAsFixed(1)} mm',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // Toplam yüksekliği hesapla
  double _calculateTotalHeight() {
    if (widget.designType != 'receipt') {
      // Etiketler için sabit yükseklik
      return widget.paperHeight > 0 ? widget.paperHeight : 40.0;
    } else {
      // Fiş için içeriklere göre yükseklik hesapla
      double totalHeight = widget.margin * 2; // Üst ve alt kenar boşlukları
      
      for (final key in widget.contentOrder) {
        if (widget.contentVisibility[key] ?? false) {
          double itemHeight = _getContentHeight(key);
          totalHeight += itemHeight + 3.0; // Her öğe arasında 3mm boşluk
        }
      }
      
      return totalHeight;
    }
  }
  
  // İçerik yüksekliğini al
  double _getContentHeight(String key) {
    // Kağıt genişliğine göre ölçeklendirme faktörü
    final scaleFactor = widget.paperWidth / 80.0; // 80mm standart genişlik referans alındı
    
    switch (key) {
      case 'logo':
        return 20.0 * scaleFactor;
      case 'businessName':
        return 10.0 * scaleFactor;
      case 'address':
        return 15.0 * scaleFactor;
      case 'phone':
        return 6.0 * scaleFactor;
      case 'taxInfo':
        return 6.0 * scaleFactor;
      case 'receiptNo':
        return 6.0 * scaleFactor;
      case 'date':
        return 6.0 * scaleFactor;
      case 'items':
        // Ürün sayısına göre dinamik yükseklik hesaplama
        final itemCount = _sampleItems.length;
        final itemHeight = 5.0 * scaleFactor; // Her ürün satırı için yükseklik
        final headerHeight = 10.0 * scaleFactor; // Başlık ve çizgiler için yükseklik
        return (itemCount * itemHeight) + headerHeight;
      case 'subtotal':
        return 6.0 * scaleFactor;
      case 'tax':
        return 6.0 * scaleFactor;
      case 'total':
        return 8.0 * scaleFactor;
      case 'paymentMethod':
        return 6.0 * scaleFactor;
      case 'barcode':
        return 15.0 * scaleFactor;
      case 'footer':
        return 8.0 * scaleFactor;
      default:
        return 6.0 * scaleFactor;
    }
  }
  
  // Otomatik yerleşim içeriği
  Widget _buildAutoLayoutContent() {
    // Kağıt genişliğine göre ölçeklendirme faktörü
    final scaleFactor = widget.paperWidth / 80.0;
    // Ara boşluk ölçeklendirmesi
    final spacingScale = scaleFactor.clamp(0.5, 1.0);
    
    // Etiket türüne göre farklı tasarımlar
    if (widget.designType == 'shelf_label') {
      return _buildShelfLabelContent(scaleFactor);
    } else if (widget.designType == 'product_label') {
      return _buildProductLabelContent(scaleFactor);
    } else if (widget.designType == 'order_label') {
      return _buildOrderLabelContent(scaleFactor);
    } else {
      // Fiş için standart tasarım
      return Padding(
        padding: EdgeInsets.all(widget.margin * _scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final key in widget.contentOrder)
              if (widget.contentVisibility[key] ?? false)
                Padding(
                  padding: EdgeInsets.only(bottom: 3 * spacingScale),
                  child: _buildContent(key),
                ),
          ],
        ),
      );
    }
  }
  
  // Raf etiketi içeriği
  Widget _buildShelfLabelContent(double scaleFactor) {
    final availableWidth = widget.paperWidth - (widget.margin * 2);
    
    return Padding(
      padding: EdgeInsets.all(widget.margin * _scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ürün adı - büyük ve kalın
          if (widget.contentVisibility['productName'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 2 * _scale),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sample Product Name',
                  style: TextStyle(
                    fontFamily: widget.fontFamily,
                    fontSize: widget.fontSize * 1.5 * _scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
          // Fiyat - büyük ve dikkat çekici
          if (widget.contentVisibility['price'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 4 * _scale),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '₺149',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 2.0 * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '.99',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 1.2 * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
          // Birim fiyatı
          if (widget.contentVisibility['unitPrice'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 2 * _scale),
              child: Text(
                'Birim Fiyatı: ₺14.99/kg',
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 0.9 * _scale,
                ),
              ),
            ),
            
          // Stok kodu ve marka
          Row(
            children: [
              // Stok kodu
              if (widget.contentVisibility['stockCode'] ?? false)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 2 * _scale),
                    child: Text(
                      'Stok: 12345',
                      style: TextStyle(
                        fontFamily: widget.fontFamily,
                        fontSize: widget.fontSize * 0.8 * _scale,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                
              // Marka
              if (widget.contentVisibility['brand'] ?? false)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 2 * _scale),
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Marka: XYZ',
                      style: TextStyle(
                        fontFamily: widget.fontFamily,
                        fontSize: widget.fontSize * 0.8 * _scale,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
            
          // Barkod
          if (widget.contentVisibility['barcode'] ?? false)
            Container(
              width: availableWidth * _scale,
              height: 30 * _scale,
              margin: EdgeInsets.only(top: 4 * _scale),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          20,
                          (index) => Container(
                            width: (index % 3 == 0) ? 2.0 * _scale : 1.0 * _scale,
                            color: index % 2 == 0 ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '8690123456789',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.7 * _scale,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  // Ürün etiketi içeriği
  Widget _buildProductLabelContent(double scaleFactor) {
    final availableWidth = widget.paperWidth - (widget.margin * 2);
    
    return Padding(
      padding: EdgeInsets.all(widget.margin * _scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ürün resmi
          if (widget.contentVisibility['productImage'] ?? false)
            Container(
              width: availableWidth * 0.7 * _scale,
              height: availableWidth * 0.7 * _scale,
              margin: EdgeInsets.only(bottom: 8 * _scale),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4 * _scale),
              ),
              child: Center(
                child: Icon(Icons.image, size: 48 * _scale),
              ),
            ),
            
          // Ürün adı
          if (widget.contentVisibility['productName'] ?? false)
            Container(
              width: availableWidth * _scale,
              margin: EdgeInsets.only(bottom: 4 * _scale),
              child: Text(
                'Örnek Ürün Adı',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 1.2 * _scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
          // Fiyat
          if (widget.contentVisibility['price'] ?? false)
            Container(
              margin: EdgeInsets.symmetric(vertical: 4 * _scale),
              padding: EdgeInsets.symmetric(horizontal: 12 * _scale, vertical: 4 * _scale),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4 * _scale),
              ),
              child: Text(
                '₺149.99',
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 1.5 * _scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            
          // Açıklama
          if (widget.contentVisibility['description'] ?? false)
            Container(
              width: availableWidth * _scale,
              margin: EdgeInsets.symmetric(vertical: 4 * _scale),
              child: Text(
                'Ürün açıklaması burada yer alacak. Kısa ve öz bir açıklama metni.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 0.8 * _scale,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            
          // Stok kodu ve marka
          Container(
            width: availableWidth * _scale,
            margin: EdgeInsets.only(top: 4 * _scale),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.contentVisibility['stockCode'] ?? false)
                  Text(
                    'Stok: 12345',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.8 * _scale,
                    ),
                  ),
                if (widget.contentVisibility['brand'] ?? false)
                  Text(
                    'Marka: XYZ',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.8 * _scale,
                    ),
                  ),
              ],
            ),
          ),
            
          // Barkod
          if (widget.contentVisibility['barcode'] ?? false)
            Container(
              width: availableWidth * _scale,
              height: 40 * _scale,
              margin: EdgeInsets.only(top: 8 * _scale),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          30,
                          (index) => Container(
                            width: (index % 3 == 0) ? 2.0 * _scale : 1.0 * _scale,
                            color: index % 2 == 0 ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '8690123456789',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.7 * _scale,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  // Sipariş etiketi içeriği
  Widget _buildOrderLabelContent(double scaleFactor) {
    final availableWidth = widget.paperWidth - (widget.margin * 2);
    
    return Padding(
      padding: EdgeInsets.all(widget.margin * _scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sipariş numarası
          if (widget.contentVisibility['orderNo'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.only(bottom: 4 * _scale),
              child: Row(
                children: [
                  Text(
                    'Sipariş No: ',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'S12345',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                    ),
                  ),
                ],
              ),
            ),
            
          // Tarih
          if (widget.contentVisibility['date'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.only(bottom: 4 * _scale),
              child: Row(
                children: [
                  Text(
                    'Tarih: ',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '01.06.2023',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                    ),
                  ),
                ],
              ),
            ),
            
          // Müşteri adı
          if (widget.contentVisibility['customerName'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.only(bottom: 4 * _scale),
              child: Row(
                children: [
                  Text(
                    'Müşteri: ',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Ahmet Yılmaz',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                    ),
                  ),
                ],
              ),
            ),
            
          // Müşteri telefonu
          if (widget.contentVisibility['customerPhone'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.only(bottom: 4 * _scale),
              child: Row(
                children: [
                  Text(
                    'Telefon: ',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '0555 123 4567',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                    ),
                  ),
                ],
              ),
            ),
            
          // Teslimat adresi
          if (widget.contentVisibility['deliveryAddress'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 4 * _scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Teslimat Adresi:',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Sample Address, Sample Street No:123, Sample City',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.9 * _scale,
                    ),
                  ),
                ],
              ),
            ),
            
          // Ürünler
          if (widget.contentVisibility['items'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 4 * _scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ürünler:',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4 * _scale),
                  // Ürün listesi
                  ...List.generate(3, (index) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: 2 * _scale),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ürün ${index + 1}',
                            style: TextStyle(
                              fontFamily: widget.fontFamily,
                              fontSize: widget.fontSize * 0.9 * _scale,
                            ),
                          ),
                          Text(
                            '${index + 1} x ${(index + 1) * 10}.99 TL',
                            style: TextStyle(
                              fontFamily: widget.fontFamily,
                              fontSize: widget.fontSize * 0.9 * _scale,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            
          // Toplam
          if (widget.contentVisibility['total'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 4 * _scale),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Toplam:',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 1.1 * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '65.97 TL',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 1.1 * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
          // Notlar
          if (widget.contentVisibility['notes'] ?? false)
            Container(
              width: availableWidth * _scale,
              padding: EdgeInsets.symmetric(vertical: 4 * _scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notlar:',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * _scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Lütfen kapıda bekleyin, zile basmayın.',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.9 * _scale,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            
          // Barkod
          if (widget.contentVisibility['barcode'] ?? false)
            Container(
              width: availableWidth * _scale,
              height: 40 * _scale,
              margin: EdgeInsets.only(top: 8 * _scale),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          30,
                          (index) => Container(
                            width: (index % 3 == 0) ? 2.0 * _scale : 1.0 * _scale,
                            color: index % 2 == 0 ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'S12345-01062023',
                    style: TextStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize * 0.7 * _scale,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  // İçerik oluşturucu
  Widget _buildContent(String key) {
    // İçerik genişliği kağıt genişliğine göre sınırlandırılıyor
    final availableWidth = widget.paperWidth - (widget.margin * 2);
    // Kağıt genişliğine göre ölçeklendirme faktörü
    final scaleFactor = widget.paperWidth / 80.0;
    // Font boyutu ölçeklendirmesi - 58mm için 5pt baz alındı
    final baseFontSize = 5.0;
    final fontScale = (widget.fontSize / baseFontSize).clamp(0.8, 1.5);
    
    switch (key) {
      case 'logo':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4 * scaleFactor),
          ),
          child: Center(
            child: Icon(Icons.image, size: 24 * scaleFactor),
          ),
        );
      
      case 'businessName':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'SAMPLE BUSINESS',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * 1.2 * fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      
      case 'address':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Sample Address, Sample Street No:123\nSample City',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'phone':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Tel: 0123 456 78 90',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'taxInfo':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Vergi No: 1234567890',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'receiptNo':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Fiş No: 12345',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'date':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Tarih: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute}',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'items':
        // Ürün sayısına göre dinamik yükseklik hesaplama
        final itemCount = _sampleItems.length;
        final itemHeight = 5.0 * scaleFactor; // Her ürün satırı için yükseklik
        final headerHeight = 10.0 * scaleFactor; // Başlık ve çizgiler için yükseklik
        final calculatedHeight = (itemCount * itemHeight) + headerHeight;
        
        return Container(
          width: availableWidth,
          // Sabit yükseklik yerine hesaplanan yüksekliği kullan
          height: calculatedHeight * _scale,
          child: Column(
            mainAxisSize: MainAxisSize.min, // İçeriğe göre boyutlandır
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 2 * scaleFactor),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Ürün',
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontSize: widget.fontSize * fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        'Adet x Fiyat',
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontSize: widget.fontSize * fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Tutar',
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontSize: widget.fontSize * fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2 * scaleFactor),
              Divider(color: Colors.grey.shade300, height: 1),
              SizedBox(height: 2 * scaleFactor),
              // Ürün listesini dinamik oluştur
              ...List.generate(_sampleItems.length, (index) {
                final item = _sampleItems[index];
                return _buildItemRow(
                  item['name'] as String,
                  item['quantity'] as int,
                  item['price'] as double,
                  fontScale
                );
              }),
            ],
          ),
        );
      
      case 'subtotal':
        // Ara toplam hesaplama
        double subtotal = 0;
        for (var item in _sampleItems) {
          subtotal += (item['quantity'] as int) * (item['price'] as double);
        }
        
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              'Ara Toplam: ${subtotal.toStringAsFixed(2)} TL',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'tax':
        // KDV hesaplama
        double subtotal = 0;
        for (var item in _sampleItems) {
          subtotal += (item['quantity'] as int) * (item['price'] as double);
        }
        double tax = subtotal * 0.18;
        
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              'KDV (%18): ${tax.toStringAsFixed(2)} TL',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'total':
        // Toplam hesaplama
        double subtotal = 0;
        for (var item in _sampleItems) {
          subtotal += (item['quantity'] as int) * (item['price'] as double);
        }
        double tax = subtotal * 0.18;
        double total = subtotal + tax;
        
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              'TOPLAM: ${total.toStringAsFixed(2)} TL',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * 1.2 * fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      
      case 'paymentMethod':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Ödeme Yöntemi: Nakit',
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
              ),
            ),
          ),
        );
      
      case 'barcode':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: availableWidth * 0.8,
                height: _getContentHeight(key) * 0.5 * _scale,
                color: Colors.black,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    15,
                    (index) => Container(
                      width: 1.5 * _scale * scaleFactor,
                      color: index % 2 == 0 ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 2 * scaleFactor),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '1234567890123',
                  style: TextStyle(
                    fontFamily: widget.fontFamily,
                    fontSize: widget.fontSize * 0.8 * fontScale,
                  ),
                ),
              ),
            ],
          ),
        );
      
      case 'footer':
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Bizi tercih ettiğiniz için teşekkür ederiz!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize * fontScale,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        );
      
      default:
        return Container(
          width: availableWidth,
          height: _getContentHeight(key) * _scale,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4 * scaleFactor),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _contentTitles[key] ?? key,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * fontScale,
                ),
              ),
            ),
          ),
        );
    }
  }
  
  // Ürün satırı
  Widget _buildItemRow(String name, int quantity, double price, double fontScale) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1 * fontScale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 0.9 * fontScale,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                '$quantity x ${price.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 0.9 * fontScale,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${(quantity * price).toStringAsFixed(2)} TL',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: widget.fontSize * 0.9 * fontScale,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Kontrol paneli
  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Yakınlaştırma kontrolü
          const Text('Yakınlaştırma:'),
          Slider(
            value: _scale,
            min: 0.5,
            max: 4.0,
            divisions: 7,
            label: _scale.toStringAsFixed(1),
            onChanged: (value) {
              setState(() {
                _scale = value;
              });
            },
          ),
        ],
      ),
    );
  }
} 
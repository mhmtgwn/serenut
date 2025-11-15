
/// Aygıt tipleri için enum
enum DeviceType {
  printer, // Yazıcı
  nfcReader, // NFC Okuyucu
  barcodeScanner, // Barkod Okuyucu
}

/// Aygıt için veri modeli
class DeviceModel {
  final String id; // Benzersiz ID
  final String name; // Aygıt adı
  final DeviceType type; // Aygıt tipi
  final String? protocol; // Yazıcı protokolü (ESC/POS, TSC, CPCL, ZPL)
  final bool isInternal; // Dahili/otomatik tespit edilen mi yoksa harici/manuel eklenen mi?
  
  // Yapılandırıcı
  DeviceModel({
    required this.id,
    required this.name,
    required this.type,
    this.protocol,
    required this.isInternal,
  });
} 
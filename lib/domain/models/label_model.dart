// lib/domain/models/label_model.dart
class LabelModel {
  final String productName;
  final double weight;
  final double price;
  final String? barcode;
  final String qrData;
  final DateTime timestamp;
  final String? batchNo;

  LabelModel({
    required this.productName,
    required this.weight,
    required this.price,
    this.barcode,
    required this.qrData,
    required this.timestamp,
    this.batchNo,
  });

  Map<String, dynamic> toMap() => {
        'productName': productName,
        'weight': weight,
        'price': price,
        'barcode': barcode,
        'qrData': qrData,
        'timestamp': timestamp.toIso8601String(),
        'batchNo': batchNo,
      };

  factory LabelModel.fromMap(Map<String, dynamic> map) => LabelModel(
        productName: map['productName'] as String,
        weight: (map['weight'] as num).toDouble(),
        price: (map['price'] as num).toDouble(),
        barcode: map['barcode'] as String?,
        qrData: map['qrData'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        batchNo: map['batchNo'] as String?,
      );
}

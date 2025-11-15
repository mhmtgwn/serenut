class Order {
  final int? id;
  final String orderNumber;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final double total;
  final String status; // pending, preparing, ready, delivered
  final String paymentMethod; // cash, card
  final String? notes;
  final String createdAt;

  Order({
    this.id,
    required this.orderNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.total,
    required this.status,
    required this.paymentMethod,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'total': total,
      'status': status,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'],
      orderNumber: map['order_number'],
      customerId: map['customer_id'],
      customerName: map['customer_name'],
      customerPhone: map['customer_phone'],
      total: map['total'],
      status: map['status'],
      paymentMethod: map['payment_method'],
      notes: map['notes'],
      createdAt: map['created_at'],
    );
  }
}

class OrderItem {
  final int? id;
  final int orderId;
  final int productId;
  final String productName;
  final int quantity;
  final double price;
  final double subtotal;

  OrderItem({
    this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.subtotal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'price': price,
      'subtotal': subtotal,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'],
      orderId: map['order_id'],
      productId: map['product_id'],
      productName: map['product_name'],
      quantity: map['quantity'],
      price: map['price'],
      subtotal: map['subtotal'],
    );
  }
}

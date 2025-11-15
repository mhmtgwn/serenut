class Customer {
  final int? id;
  final String name;
  final String phone;
  final String? address;
  final String createdAt;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'created_at': createdAt,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      address: map['address'],
      createdAt: map['created_at'],
    );
  }
}

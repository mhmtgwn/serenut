import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  group('CustomerEntity Address & Compatibility Tests', () {
    test('CustomerEntity stores and serializes address correctly', () {
      final now = DateTime.now();
      final customer = CustomerEntity(
        id: 'cust-addr-1',
        name: 'AHMET YILMAZ',
        phone: '05551234567',
        address: 'Atatürk Cad. No: 12 Kat: 3 Daire: 5',
        balance: 150.0,
        createdAt: now,
      );

      expect(customer.address, equals('Atatürk Cad. No: 12 Kat: 3 Daire: 5'));
      expect(customer.email, equals('')); // Default email backwards compatibility

      final map = customer.toMap();
      expect(map['address'], equals('Atatürk Cad. No: 12 Kat: 3 Daire: 5'));
      expect(map['email'], equals(''));

      final fromMap = CustomerEntity.fromMap(map);
      expect(fromMap.id, equals('cust-addr-1'));
      expect(fromMap.name, equals('AHMET YILMAZ'));
      expect(fromMap.address, equals('Atatürk Cad. No: 12 Kat: 3 Daire: 5'));
    });

    test('CustomerEntity handles null/empty address seamlessly', () {
      final customer = CustomerEntity(
        id: 'cust-no-addr',
        name: 'MEHMET DEMİR',
        phone: '05321112233',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      expect(customer.address, isNull);
      expect(customer.email, equals(''));

      final map = customer.toMap();
      expect(map['address'], equals(''));

      final fromMap = CustomerEntity.fromMap(map);
      expect(fromMap.address, isNull);
    });

    test('CustomerEntity copyWith can update address', () {
      final customer = CustomerEntity(
        id: 'cust-copy',
        name: 'AYŞE KAYA',
        phone: '05443332211',
        balance: 50.0,
        createdAt: DateTime.now(),
      );

      final updated = customer.copyWith(address: 'Yeni Mahalle 4. Sokak No: 8');
      expect(updated.address, equals('Yeni Mahalle 4. Sokak No: 8'));
      expect(updated.name, equals('AYŞE KAYA'));
    });
  });
}

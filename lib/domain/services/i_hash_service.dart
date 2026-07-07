import 'dart:typed_data';

abstract class IHashService {
  String hashPassword(String password);
  bool verifyPassword(String password, String storedHash);
  bool isLegacyHash(String storedHash);
  Uint8List deriveKey({
    required String password,
    required Uint8List salt,
    required int iterations,
    required int keyLength,
  });
}

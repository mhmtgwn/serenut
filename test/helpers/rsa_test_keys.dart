import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Ephemeral RSA key material for signature tests. No reusable private key is
/// stored in the repository.
class RsaTestKeys {
  RsaTestKeys._(this.privateKey, this.publicKey);

  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;

  String get modulus => publicKey.modulus!.toString();

  static RsaTestKeys generate() {
    final random = FortunaRandom();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    random.seed(KeyParameter(seed));

    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    return RsaTestKeys._(
      pair.privateKey as RSAPrivateKey,
      pair.publicKey as RSAPublicKey,
    );
  }

  Uint8List sign(List<int> payload) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return signer.generateSignature(Uint8List.fromList(payload)).bytes;
  }
}

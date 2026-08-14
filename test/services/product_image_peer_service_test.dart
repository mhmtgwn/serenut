import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/product_image_peer_service.dart';

void main() {
  const hash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('parses portable content-addressed product image references', () {
    const value = 'device-image://$hash.webp';

    expect(ProductImagePeerService.isDeviceImageUri(value), isTrue);
    expect(ProductImagePeerService.imageIdFromUri(value), '$hash.webp');
  });

  test('rejects paths and unsupported extensions as peer image ids', () {
    expect(
      ProductImagePeerService.imageIdFromUri('device-image://../../secret.jpg'),
      isNull,
    );
    expect(
      ProductImagePeerService.imageIdFromUri('device-image://$hash.exe'),
      isNull,
    );
    expect(ProductImagePeerService.imageIdFromUri('https://example.com/a.jpg'),
        isNull);
  });
}

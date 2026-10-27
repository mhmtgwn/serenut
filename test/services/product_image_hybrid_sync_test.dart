import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:serenutos/infrastructure/services/product_image_peer_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Directory imagesDir;
  late ProductImagePeerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('serenut_image_hybrid_test_');
    imagesDir = Directory(p.join(tempDir.path, 'product_images'));
    await imagesDir.create(recursive: true);

    service = ProductImagePeerService.instance;
    service.setImageDirectory(imagesDir);
    service.setCloudOriginUrl('https://api.serenut.com');
    service.setPeerToken('test-peer-token');
  });

  tearDown(() async {
    service.setHttpClient(null);
    service.setCloudOriginUrl(null);
    service.setImageDirectory(null);
    service.setPeerToken(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('uploadToCloudOrigin verifies hash and sends binary payload to cloud origin', () async {
    final payload = utf8.encode('product-image-content-sample');
    final hash = sha256.convert(payload).toString();
    final imageId = '$hash.jpg';

    final localFile = File(p.join(imagesDir.path, imageId));
    await localFile.writeAsBytes(payload);

    var requestedUrl = '';
    var requestedMethod = '';
    Map<String, String>? requestedHeaders;
    List<int>? requestedBody;

    final mockClient = MockClient((request) async {
      requestedUrl = request.url.toString();
      requestedMethod = request.method;
      requestedHeaders = request.headers;
      requestedBody = request.bodyBytes;
      return http.Response(jsonEncode({'success': true, 'imageId': imageId}), 201);
    });

    service.setHttpClient(mockClient);

    final success = await service.uploadToCloudOrigin(localFile, imageId);

    expect(success, isTrue);
    expect(requestedMethod, 'POST');
    expect(requestedUrl, 'https://api.serenut.com/api/v1/products/image');
    expect(requestedHeaders?['x-image-id'], imageId);
    expect(requestedHeaders?['x-serenut-peer-token'], 'test-peer-token');
    expect(requestedHeaders?['content-type'], 'image/jpeg');
    expect(requestedBody, payload);
  });

  test('downloadFromCloudOrigin fetches from origin, verifies hash, and saves to directory', () async {
    final payload = utf8.encode('downloadable-product-image-bytes');
    final hash = sha256.convert(payload).toString();
    final imageId = '$hash.png';

    final mockClient = MockClient((request) async {
      if (request.url.toString() == 'https://api.serenut.com/uploads/product-images/$imageId') {
        return http.Response.bytes(payload, 200);
      }
      return http.Response('Not Found', 404);
    });

    service.setHttpClient(mockClient);

    final success = await service.downloadFromCloudOrigin(imageId, imagesDir);

    expect(success, isTrue);
    final savedFile = File(p.join(imagesDir.path, imageId));
    expect(await savedFile.exists(), isTrue);
    expect(await savedFile.readAsBytes(), payload);
  });

  test('downloadFromCloudOrigin rejects corrupted/tampered bytes when SHA-256 does not match', () async {
    final correctPayload = utf8.encode('authentic-image-bytes');
    final hash = sha256.convert(correctPayload).toString();
    final imageId = '$hash.jpg';

    final corruptPayload = utf8.encode('tampered-or-corrupt-payload');

    final mockClient = MockClient((request) async {
      return http.Response.bytes(corruptPayload, 200);
    });

    service.setHttpClient(mockClient);

    final success = await service.downloadFromCloudOrigin(imageId, imagesDir);

    expect(success, isFalse);
    final savedFile = File(p.join(imagesDir.path, imageId));
    expect(await savedFile.exists(), isFalse);
  });

  test('syncMissingImages gracefully falls back to Cloud Origin when LAN peers are offline', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            image_url TEXT,
            is_deleted INTEGER DEFAULT 0
          )
        ''');
      },
    );

    final payload = utf8.encode('cloud-fallback-image-data');
    final hash = sha256.convert(payload).toString();
    final imageId = '$hash.webp';

    await db.insert('products', {
      'id': 'prod-101',
      'image_url': 'device-image://$imageId',
      'is_deleted': 0,
    });

    final mockClient = MockClient((request) async {
      if (request.url.toString().contains(imageId)) {
        return http.Response.bytes(payload, 200);
      }
      return http.Response('Not Found', 404);
    });

    service.setHttpClient(mockClient);

    final downloadedCount = await service.syncMissingImages(db);

    expect(downloadedCount, 1);
    final targetFile = File(p.join(imagesDir.path, imageId));
    expect(await targetFile.exists(), isTrue);
    expect(await targetFile.readAsBytes(), payload);

    await db.close();
  });
}

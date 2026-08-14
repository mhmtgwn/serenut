import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

/// Keeps product images exclusively on Serenut devices.
///
/// The cloud only sees a content-addressed `device-image://...` reference.
/// Image bytes are advertised and copied directly between devices on the same
/// LAN. A missing source is harmless: the next sync pass retries it.
class ProductImagePeerService {
  ProductImagePeerService._();

  static final ProductImagePeerService instance = ProductImagePeerService._();
  static const int _httpPort = 48731;
  static const int _discoveryPort = 48732;
  static final RegExp _imageIdPattern =
      RegExp(r'^[a-f0-9]{64}\.(?:jpg|jpeg|png|webp)$');

  HttpServer? _server;
  RawDatagramSocket? _discovery;
  String? _scope;
  String? _peerToken;
  Directory? _imageDirectory;
  final Set<InternetAddress> _peers = <InternetAddress>{};

  static bool isDeviceImageUri(String? value) =>
      value?.trim().toLowerCase().startsWith('device-image://') == true;

  static String? imageIdFromUri(String? value) {
    if (!isDeviceImageUri(value)) return null;
    final uri = Uri.tryParse(value!.trim());
    final id = uri?.host.isNotEmpty == true
        ? uri!.host
        : (uri?.path.startsWith('/') == true
            ? uri!.path.substring(1)
            : uri?.path);
    return id != null && _imageIdPattern.hasMatch(id) ? id : null;
  }

  static Future<String?> localPathForUri(String? value) async {
    final id = imageIdFromUri(value);
    if (id == null) return null;
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'product_images', id);
  }

  Future<void> start(String companyScope) async {
    if (companyScope.trim().isEmpty) return;
    final nextScope = sha256.convert(utf8.encode(companyScope)).toString();
    if (_scope != nextScope) _peers.clear();
    _scope = nextScope;
    _peerToken = sha256
        .convert(utf8.encode('serenut-product-images:$companyScope'))
        .toString();
    final support = await getApplicationSupportDirectory();
    _imageDirectory = Directory(p.join(support.path, 'product_images'));
    await _imageDirectory!.create(recursive: true);

    if (_server == null) {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _httpPort,
      );
      _server!.listen(_serve, onError: (_) {});
    }

    if (_discovery == null) {
      _discovery = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _discovery!.broadcastEnabled = true;
      _discovery!.listen(_handleDiscovery, onError: (_) {});
      Timer.periodic(
        const Duration(seconds: 20),
        (_) => _announce(),
      );
    }
    _announce();
  }

  Future<void> prepareLocalImages(Database db) async {
    final directory = _imageDirectory;
    if (directory == null) return;
    final rows = await db.query(
      'products',
      where: "image_url IS NOT NULL AND TRIM(image_url) <> ''",
    );
    for (final row in rows) {
      final current = row['image_url']?.toString().trim() ?? '';
      if (current.isEmpty ||
          isDeviceImageUri(current) ||
          _isNetworkUrl(current)) {
        continue;
      }
      final source = File(current);
      if (!await source.exists()) continue;
      final digest = await sha256.bind(source.openRead()).first;
      final extension = _safeExtension(current);
      final imageId = '${digest.toString()}.$extension';
      final target = File(p.join(directory.path, imageId));
      if (!await target.exists()) {
        final temporary = File('${target.path}.part');
        await source.copy(temporary.path);
        await temporary.rename(target.path);
      }
      final portableUri = 'device-image://$imageId';
      await db.update(
        'products',
        {'image_url': portableUri},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      await SyncOutboxV4.enqueue(
        db,
        entityType: 'product',
        entityId: row['id'].toString(),
        operation: 'UPSERT',
        payload: {...row, 'image_url': portableUri, 'is_synced': 0},
      );
    }
  }

  Future<int> syncMissingImages(Database db) async {
    final directory = _imageDirectory;
    if (directory == null) return 0;
    final rows = await db.query(
      'products',
      columns: const ['image_url'],
      distinct: true,
      where: "image_url LIKE 'device-image://%' AND is_deleted = 0",
    );
    final missing = <String>[];
    for (final row in rows) {
      final id = imageIdFromUri(row['image_url']?.toString());
      if (id != null && !await File(p.join(directory.path, id)).exists()) {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return 0;
    _announce();
    await Future<void>.delayed(const Duration(milliseconds: 450));

    final availability = <InternetAddress, Set<String>>{};
    for (final peer in List<InternetAddress>.from(_peers)) {
      final manifest = await _fetchManifest(peer);
      if (manifest != null) availability[peer] = manifest;
    }
    var downloaded = 0;
    for (final imageId in missing) {
      for (final peer in availability.keys) {
        if (!availability[peer]!.contains(imageId)) continue;
        if (await _download(peer, imageId, directory)) {
          downloaded++;
          break;
        }
      }
    }
    return downloaded;
  }

  void _handleDiscovery(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _discovery?.receive()) != null) {
      try {
        final message = jsonDecode(utf8.decode(datagram!.data)) as Map;
        if (message['kind'] == 'serenut-product-images' &&
            message['scope'] == _scope &&
            message['port'] == _httpPort &&
            !datagram.address.isLoopback) {
          _peers.add(datagram.address);
        }
      } catch (_) {
        // Ignore unrelated LAN broadcast traffic.
      }
    }
  }

  void _announce() {
    final socket = _discovery;
    final scope = _scope;
    if (socket == null || scope == null) return;
    final bytes = utf8.encode(jsonEncode({
      'kind': 'serenut-product-images',
      'scope': scope,
      'port': _httpPort,
    }));
    socket.send(bytes, InternetAddress('255.255.255.255'), _discoveryPort);
  }

  Future<void> _serve(HttpRequest request) async {
    try {
      if (request.method != 'GET' ||
          request.headers.value('x-serenut-peer-token') != _peerToken ||
          request.uri.pathSegments.length != 2 ||
          request.uri.pathSegments.first != 'product-images') {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      final imageId = request.uri.pathSegments.last.toLowerCase();
      if (imageId == 'manifest') {
        final ids = await _imageDirectory!
            .list()
            .where((entry) => entry is File)
            .map((entry) => p.basename(entry.path).toLowerCase())
            .where(_imageIdPattern.hasMatch)
            .toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'images': ids}));
        return;
      }
      if (!_imageIdPattern.hasMatch(imageId)) {
        request.response.statusCode = HttpStatus.badRequest;
        return;
      }
      final file = File(p.join(_imageDirectory!.path, imageId));
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      request.response.headers.contentType =
          ContentType('image', _mimeSubtype(imageId));
      request.response.headers.contentLength = await file.length();
      await request.response.addStream(file.openRead());
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  Future<Set<String>?> _fetchManifest(InternetAddress peer) async {
    try {
      final response = await http.get(
        Uri.parse('http://${peer.address}:$_httpPort/product-images/manifest'),
        headers: {'x-serenut-peer-token': _peerToken!},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok ||
          response.bodyBytes.length > 2 * 1024 * 1024) {
        return null;
      }
      final body = jsonDecode(response.body) as Map;
      return ((body['images'] as List?) ?? const [])
          .map((value) => value.toString().toLowerCase())
          .where(_imageIdPattern.hasMatch)
          .toSet();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _download(
    InternetAddress peer,
    String imageId,
    Directory directory,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('http://${peer.address}:$_httpPort/product-images/$imageId'),
        headers: {'x-serenut-peer-token': _peerToken!},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        return false;
      }
      final expectedHash = imageId.substring(0, 64);
      if (sha256.convert(response.bodyBytes).toString() != expectedHash) {
        return false;
      }
      final target = File(p.join(directory.path, imageId));
      final temporary = File('${target.path}.part');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(target.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isNetworkUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:');
  }

  static String _safeExtension(String value) {
    final extension = p.extension(value).toLowerCase().replaceFirst('.', '');
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
        ? extension
        : 'jpg';
  }

  static String _mimeSubtype(String imageId) =>
      imageId.endsWith('.jpg') ? 'jpeg' : p.extension(imageId).substring(1);
}

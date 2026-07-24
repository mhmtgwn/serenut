// lib/presentation/widgets/product_image.dart
// Cross-platform Product Image Widget
// Renders network images (Web/fallback), file images (Native), or falls back to barcode-matched local image files.

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:serenutos/config/environment.dart';

final appDocumentsDirectoryProvider = FutureProvider<Directory>((ref) async {
  if (kIsWeb) {
    throw UnsupportedError('Documents directory is not supported on Web');
  }
  return getApplicationDocumentsDirectory();
});

class ProductImage extends ConsumerWidget {
  final String? imageUrl;
  final String barcode;
  final double size;

  static final Map<String, bool> _imageExistsCache = {};

  static void clearCache() {
    _imageExistsCache.clear();
  }

  const ProductImage({
    this.imageUrl,
    required this.barcode,
    this.size = 50.0,
    super.key,
  });

  static bool _isNetworkUrl(String url) {
    final clean = url.trim().toLowerCase();
    return clean.startsWith('http://') ||
        clean.startsWith('https://') ||
        clean.startsWith('data:') ||
        clean.startsWith('/uploads') ||
        clean.startsWith('uploads/') ||
        clean.startsWith('/api/') ||
        clean.startsWith('/shared/');
  }

  static String _toAbsoluteUrl(String path) {
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:')) {
      return path;
    }
    final baseUri = Uri.parse(EnvironmentConfig.current.apiBaseUrl);
    final origin =
        '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ":${baseUri.port}" : ""}';
    return '$origin${path.startsWith('/') ? path : '/$path'}';
  }

  static String _resolveLocalPath(String path, String documentsDir) {
    if (p.isAbsolute(path)) {
      if (path.contains('product_images')) {
        final relativePart = path.substring(path.indexOf('product_images'));
        return p.join(documentsDir, relativePart);
      }
      return p.join(documentsDir, 'product_images', p.basename(path));
    }
    return p.join(documentsDir, path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((imageUrl == null || imageUrl!.isEmpty) && barcode.isEmpty) {
      return _buildPlaceholder();
    }

    // 1. Web execution
    if (kIsWeb) {
      if (imageUrl != null &&
          imageUrl!.isNotEmpty &&
          _isNetworkUrl(imageUrl!)) {
        return _buildNetworkImage(context, _toAbsoluteUrl(imageUrl!));
      }
      return _buildPlaceholder();
    }

    // 2. Native execution with directory resolution
    final docsDirAsync = ref.watch(appDocumentsDirectoryProvider);
    return docsDirAsync.when(
      data: (dir) {
        if (imageUrl != null && imageUrl!.isNotEmpty) {
          if (_isNetworkUrl(imageUrl!)) {
            return _buildNetworkImage(context, _toAbsoluteUrl(imageUrl!));
          } else {
            final resolvedPath = _resolveLocalPath(imageUrl!, dir.path);
            if (File(resolvedPath).existsSync()) {
              return _buildFileImage(context, resolvedPath);
            }
          }
        }

        // Fallback to barcode-matched image file
        final localPath = p.join(dir.path, 'product_images', '$barcode.jpg');
        final exists =
            _imageExistsCache[barcode] ??= File(localPath).existsSync();
        if (exists) {
          return _buildFileImage(context, localPath);
        }
        return _buildPlaceholder();
      },
      loading: () => SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
      error: (_, __) => _buildPlaceholder(),
    );
  }

  Widget _buildNetworkImage(BuildContext context, String url) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (size * dpr).round();
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
    );
  }

  Widget _buildFileImage(BuildContext context, String path) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (size * dpr).round();
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFF1F5F9),
      child: Icon(
        Icons.image_outlined,
        color: const Color(0xFF94A3B8),
        size: size * 0.45,
      ),
    );
  }
}

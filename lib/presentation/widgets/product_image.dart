// lib/presentation/widgets/product_image.dart
// Cross-platform Product Image Widget
// Renders network images (Web/fallback), file images (Native), or falls back to barcode-matched local image files.

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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

  const ProductImage({
    this.imageUrl,
    required this.barcode,
    this.size = 50.0,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((imageUrl == null || imageUrl!.isEmpty) && barcode.isEmpty) {
      return _buildPlaceholder();
    }

    // 1. Web execution
    if (kIsWeb) {
      if (imageUrl != null &&
          (imageUrl!.startsWith('http') || imageUrl!.startsWith('data:'))) {
        return _buildNetworkImage(context, imageUrl!);
      }
      return _buildPlaceholder();
    }

    // 2. Native: explicit imageUrl provided
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (imageUrl!.startsWith('http') || imageUrl!.startsWith('data:')) {
        return _buildNetworkImage(context, imageUrl!);
      } else {
        return _buildFileImage(context, imageUrl!);
      }
    }

    // 3. Native: fallback to barcode-matched image file
    final docsDirAsync = ref.watch(appDocumentsDirectoryProvider);
    return docsDirAsync.when(
      data: (dir) {
        final localPath = p.join(dir.path, 'product_images', '$barcode.jpg');
        final file = File(localPath);
        if (file.existsSync()) {
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

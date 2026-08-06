import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class PrintAssetEncoder {
  const PrintAssetEncoder();

  Future<Uint8List?> loadLogo(String? source) async {
    try {
      if (source != null && source.startsWith('data:image/')) {
        final comma = source.indexOf(',');
        return comma < 0 ? null : base64Decode(source.substring(comma + 1));
      }
      if (!kIsWeb &&
          source != null &&
          (source.startsWith('https://') || source.startsWith('http://'))) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        try {
          final response =
              await (await client.getUrl(Uri.parse(source))).close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            return null;
          }
          return Uint8List.fromList(await response
              .fold<List<int>>([], (all, part) => all..addAll(part)));
        } finally {
          client.close(force: true);
        }
      }
      if (!kIsWeb &&
          source != null &&
          source.isNotEmpty &&
          File(source).existsSync()) {
        return File(source).readAsBytes();
      }
      final data = await rootBundle.load('assets/logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Uint8List? toEscPosRaster(Uint8List source, {required int maxWidth}) {
    final decoded = img.decodeImage(source);
    if (decoded == null) return null;
    var targetWidth = decoded.width.clamp(8, maxWidth);
    targetWidth = (targetWidth ~/ 8) * 8;
    var resized = img.copyResize(decoded,
        width: targetWidth, interpolation: img.Interpolation.cubic);
    final maxHeight = maxWidth <= 320 ? 96 : 128;
    if (resized.height > maxHeight) {
      resized = img.copyResize(resized,
          height: maxHeight, interpolation: img.Interpolation.cubic);
      final aligned = (resized.width ~/ 8) * 8;
      resized = img.copyResize(resized, width: aligned.clamp(8, maxWidth));
    }
    final widthBytes = (resized.width + 7) ~/ 8;
    final bytes = <int>[
      0x1D,
      0x76,
      0x30,
      0,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      resized.height & 0xFF,
      (resized.height >> 8) & 0xFF,
    ];
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < widthBytes * 8; x += 8) {
        var value = 0;
        for (var bit = 0; bit < 8; bit++) {
          final px = x + bit;
          if (px >= resized.width) continue;
          final pixel = resized.getPixel(px, y);
          if (pixel.a < 128) continue;
          final luminance = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
          if (luminance < 128) {
            value |= 1 << (7 - bit);
          }
        }
        bytes.add(value);
      }
    }
    return Uint8List.fromList(bytes);
  }
}

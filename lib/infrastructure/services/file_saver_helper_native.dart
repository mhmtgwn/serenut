// lib/infrastructure/services/file_saver_helper_native.dart
// Native implementation of FileSaver utilizing path_provider and share_plus.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_saver_helper_interface.dart';

class FileSaverImpl implements FileSaver {
  @override
  Future<void> saveAndShareFile({
    required Uint8List bytes,
    required String filename,
    required BuildContext context,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File(p.join(tempDir.path, filename));
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Serenut POS Ürün Kataloğu Dışa Aktar',
      );
    }
  }
}

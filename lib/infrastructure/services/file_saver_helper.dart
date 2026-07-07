// lib/infrastructure/services/file_saver_helper.dart
// Cross-platform FileSaver entry point utilizing conditional imports.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'file_saver_helper_interface.dart';
import 'file_saver_helper_native.dart'
    if (dart.library.html) 'file_saver_helper_web.dart';

class FileSaverHelper {
  static final FileSaver _impl = FileSaverImpl();

  static Future<void> saveAndShareFile({
    required Uint8List bytes,
    required String filename,
    required BuildContext context,
  }) {
    return _impl.saveAndShareFile(
      bytes: bytes,
      filename: filename,
      context: context,
    );
  }
}

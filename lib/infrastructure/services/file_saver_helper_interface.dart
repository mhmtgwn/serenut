// lib/infrastructure/services/file_saver_helper_interface.dart
// Cross-platform File Saver Interface

import 'dart:typed_data';
import 'package:flutter/material.dart';

abstract class FileSaver {
  Future<void> saveAndShareFile({
    required Uint8List bytes,
    required String filename,
    required BuildContext context,
  });
}

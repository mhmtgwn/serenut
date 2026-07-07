// lib/infrastructure/services/file_saver_helper_web.dart
// Web implementation of FileSaver utilizing HTML anchor elements and blobs.

import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'file_saver_helper_interface.dart';

class FileSaverImpl implements FileSaver {
  @override
  Future<void> saveAndShareFile({
    required Uint8List bytes,
    required String filename,
    required BuildContext context,
  }) async {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

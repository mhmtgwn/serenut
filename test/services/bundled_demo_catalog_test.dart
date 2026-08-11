import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';

class _UnusedProductRepository implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('bundled demo catalog is readable and contains products and images',
      () async {
    final file = File('market_data_catalog_with_images.zip');
    expect(await file.exists(), isTrue);

    final bytes = Uint8List.fromList(await file.readAsBytes());
    final parsed = await DatasetImportService(_UnusedProductRepository())
        .analyzeZip(bytes, (_, __) {});

    expect(parsed.products.length, greaterThan(1000));
    expect(parsed.images.length, greaterThan(1000));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

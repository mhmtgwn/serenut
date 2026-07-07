// lib/providers/dataset_import_provider.dart
// Riverpod Provider for DatasetImportService

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/providers/repository_providers.dart';

final datasetImportServiceProvider = FutureProvider<DatasetImportService>((ref) async {
  // Retrieve the active product repository entity asynchronously.
  final repo = await ref.watch(productRepositoryProvider.future);
  return DatasetImportService(repo);
});

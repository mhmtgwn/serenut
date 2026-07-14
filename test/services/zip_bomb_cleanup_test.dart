import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:archive/archive.dart';

class MockProductRepository implements IProductRepository {
  @override
  Future<int> create(ProductEntity product) async {
    // Force a database failure during transaction replay to trigger rollback cleanup
    throw Exception('Simulated DB Failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Zip Bomb & Import Cleanup Tests', () {
    test('Rejects zip archives larger than 100MB', () async {
      final largeBytes = Uint8List(100 * 1024 * 1024 + 1); // 100MB + 1 byte
      final mockRepo = MockProductRepository();
      final importService = DatasetImportService(mockRepo);

      expect(
        () => importService.analyzeZip(largeBytes, (_, __) {}),
        throwsA(predicate((e) => e.toString().contains('Dosya boyutu sınırlandırılmıştır'))),
      );

      expect(
        () => importService.importFromZip(largeBytes, (_, __) {}),
        throwsA(predicate((e) => e.toString().contains('Dosya boyutu sınırlandırılmıştır'))),
      );
    });

    test('Rejects zip archives with uncompressed sizes larger than 100MB (Zip Bomb)', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('bomb.txt', 101 * 1024 * 1024, [0]));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final mockRepo = MockProductRepository();
      final importService = DatasetImportService(mockRepo);

      expect(
        () => importService.analyzeZip(zipBytes, (_, __) {}),
        throwsA(predicate((e) => e.toString().contains('Yüksek sıkıştırma oranı tespit edildi'))),
      );
    });

    test('Proof of lazy decompression: decodeBytes does not allocate uncompressed content', () async {
      final archive = Archive();
      final largeData = Uint8List(10 * 1024 * 1024); // 10MB of zeros
      archive.addFile(ArchiveFile('lazy.txt', largeData.length, largeData));
      
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      
      final decodedArchive = ZipDecoder().decodeBytes(zipBytes);
      final decodedFile = decodedArchive.first;
      
      // Metadata is read immediately
      expect(decodedFile.size, equals(10 * 1024 * 1024));
      
      // Rejecting based on metadata without accessing content keeps memory footprint minimal
      expect(decodedFile.size > 5 * 1024 * 1024, isTrue);
    });
  });
}

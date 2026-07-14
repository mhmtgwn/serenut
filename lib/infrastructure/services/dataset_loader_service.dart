// lib/infrastructure/services/dataset_loader_service.dart
// POS Dataset Loader Service
// Design Evolution v3: Offline dataset mounting, hot switching, rollback, default market price mapping
// Revized: 24 Jun 2026

import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class DatasetVersion {
  final String version;
  final String timestamp;
  final int productCount;
  final int priceCount;
  final double integrityScore;

  DatasetVersion({
    required this.version,
    required this.timestamp,
    required this.productCount,
    required this.priceCount,
    required this.integrityScore,
  });

  factory DatasetVersion.fromJson(Map<String, dynamic> json) => DatasetVersion(
        version: json['version'] as String? ?? 'Unknown',
        timestamp: json['timestamp'] as String? ?? '',
        productCount: json['product_count'] as int? ?? 0,
        priceCount: json['price_count'] as int? ?? 0,
        integrityScore: (json['integrity_score'] as num?)?.toDouble() ?? 0.0,
      );
}

class DatasetLoaderService {
  final SharedPreferences _prefs;
  Database? _activeDb;
  String _activeVersion = 'None';
  String _selectedMarket = 'Migros';

  DatasetLoaderService(this._prefs) {
    _activeVersion = _prefs.getString('active_dataset_version') ?? 'None';
    _selectedMarket =
        _prefs.getString('selected_intelligence_market') ?? 'Migros';
  }

  String get activeVersion => _activeVersion;
  String get selectedMarket => _selectedMarket;
  Database? get activeDb => _activeDb;

  Future<void> init() async {
    if (_activeVersion != 'None') {
      await mountVersion(_activeVersion);
    }
  }

  Future<Directory> get _datasetsDirectory async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final path = join(appDocDir.path, 'datasets');
    return Directory(path)..createSync(recursive: true);
  }

  Future<List<DatasetVersion>> getAvailableVersions() async {
    final dir = await _datasetsDirectory;
    if (!dir.existsSync()) return [];

    final List<DatasetVersion> versions = [];
    final list = dir.listSync();
    for (final entity in list) {
      if (entity is Directory) {
        final versionFile = File(join(entity.path, 'version.json'));
        if (versionFile.existsSync()) {
          try {
            final jsonStr = versionFile.readAsStringSync();
            final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
            versions.add(DatasetVersion.fromJson(decoded));
          } catch (_) {
            // Ignore malformed version jsons
          }
        }
      }
    }
    // Sort versions descending: v3, v2, v1
    versions.sort((a, b) => b.version.compareTo(a.version));
    return versions;
  }

  Future<bool> mountVersion(String version) async {
    try {
      final dir = await _datasetsDirectory;
      final versionDir = join(dir.path, version);
      final sqlitePath = join(versionDir, 'products.sqlite');

      if (!File(sqlitePath).existsSync()) {
        return false;
      }

      // Close previous database connections
      if (_activeDb != null) {
        await _activeDb!.close();
        _activeDb = null;
      }

      // Open connection to dataset database (read-only mode)
      _activeDb = await DatabaseManager()
          .openDatabaseConnection(sqlitePath, readOnly: true);
      _activeVersion = version;
      await _prefs.setString('active_dataset_version', version);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> unmountActiveVersion() async {
    if (_activeDb != null) {
      await _activeDb!.close();
      _activeDb = null;
    }
    _activeVersion = 'None';
    await _prefs.setString('active_dataset_version', 'None');
  }

  Future<void> setSelectedMarket(String market) async {
    _selectedMarket = market;
    await _prefs.setString('selected_intelligence_market', market);
  }

  Future<List<ProductEntity>> getDatasetProducts() async {
    if (_activeDb == null) return [];

    // SQL Join Query mapping dataset products & specific market prices to ProductEntity
    final List<Map<String, dynamic>> rows = await _activeDb!.rawQuery('''
      SELECT p.barcode as id, p.name, COALESCE(p.brand, '') as description, 
             COALESCE(pr.price, 0.0) as price, 99 as quantity, p.category, 
             CAST(COALESCE(p.vat_rate, 18.0) AS INTEGER) as vat
      FROM products p
      LEFT JOIN prices pr ON p.barcode = pr.barcode AND pr.market_name = ?
    ''', [_selectedMarket]);

    return rows
        .map((row) => ProductEntity(
              id: row['id'] as String,
              name: row['name'] as String,
              description: row['description'] as String,
              price: (row['price'] as num).toDouble(),
              quantity: row['quantity'] as int,
              category: row['category'] as String,
              vat: row['vat'] as int?,
            ))
        .toList();
  }
}

// Riverpod Provider definitions for dependency injection
final datasetLoaderServiceProvider = Provider<DatasetLoaderService>((ref) {
  throw UnimplementedError(
      'Must override datasetLoaderServiceProvider in ProviderScope');
});

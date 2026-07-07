// lib/infrastructure/repositories/sqlite_business_profile_repository.dart
// SQLite implementation of IBusinessProfileRepository

import 'package:serenutos/domain/models/business_profile.dart';
import 'package:serenutos/domain/repositories/i_business_profile_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

class SqliteBusinessProfileRepository implements IBusinessProfileRepository {
  final DbGateway _gateway;

  SqliteBusinessProfileRepository(this._gateway);

  @override
  Future<BusinessProfile?> getProfile() async {
    final rows = await _gateway.query('business_profile', limit: 1);
    if (rows.isEmpty) return null;
    return BusinessProfile.fromMap(rows.first);
  }

  @override
  Future<void> saveProfile(BusinessProfile profile) async {
    // Upsert: insert or replace
    final existing = await getProfile();
    if (existing == null) {
      await _gateway.insert(
        'business_profile',
        profile.toMap(),
      );
    } else {
      await _gateway.update(
        'business_profile',
        profile.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    }
  }

  @override
  Future<void> updateProfile(BusinessProfile profile) async {
    await _gateway.update(
      'business_profile',
      profile.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }
}

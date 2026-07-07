// lib/domain/repositories/i_business_profile_repository.dart
// BusinessProfile repository interface

import 'package:serenutos/domain/models/business_profile.dart';

abstract class IBusinessProfileRepository {
  /// İşletme profilini getir (tekil kayıt)
  Future<BusinessProfile?> getProfile();

  /// İşletme profilini kaydet (insert or replace)
  Future<void> saveProfile(BusinessProfile profile);

  /// İşletme profilini güncelle
  Future<void> updateProfile(BusinessProfile profile);
}

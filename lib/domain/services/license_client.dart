// lib/domain/services/license_client.dart
// Serenut Platform — Cloud License Client
// Defines the contract and mock client implementations for remote licensing synchronization.
// Created: 04 Jul 2026

import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

abstract class LicenseClient {
  Future<CompanyLicense?> activate(String token, String deviceId);
  Future<bool> validate(String licenseId);
  Future<CompanyLicense?> refresh(String licenseId);
  Future<bool> deactivate(String licenseId, String deviceId);
  Future<bool> syncLicense(String licenseId);
}

class CloudLicenseClient implements LicenseClient {
  final ApiClient _apiClient;

  CloudLicenseClient(this._apiClient);

  @override
  Future<CompanyLicense?> activate(String token, String deviceId) async {
    final response = await _apiClient.post('/license/activate', {
      'token': token,
      'deviceId': deviceId,
    });
    if (response.isSuccess) {
      return CompanyLicense.fromJson(response.json);
    }
    return null;
  }

  @override
  Future<bool> validate(String licenseId) async {
    try {
      final response = await _apiClient.get('/license/validate?id=$licenseId');
      return response.isSuccess && response.json['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CompanyLicense?> refresh(String licenseId) async {
    final response = await _apiClient.post('/license/refresh', {
      'licenseId': licenseId,
    });
    if (response.isSuccess) {
      return CompanyLicense.fromJson(response.json);
    }
    return null;
  }

  @override
  Future<bool> deactivate(String licenseId, String deviceId) async {
    try {
      final response = await _apiClient.post('/license/deactivate', {
        'licenseId': licenseId,
        'deviceId': deviceId,
      });
      return response.isSuccess && response.json['deactivated'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> syncLicense(String licenseId) async {
    try {
      final response = await _apiClient.post('/license/sync', {
        'licenseId': licenseId,
      });
      return response.isSuccess && response.json['synced'] == true;
    } catch (_) {
      return false;
    }
  }
}

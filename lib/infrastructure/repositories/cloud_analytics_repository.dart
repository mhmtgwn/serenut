// lib/infrastructure/repositories/cloud_analytics_repository.dart
// Serenut Platform — Cloud BI Analytics Repository (Sprint 7)
// Client side interface for BI analytics endpoints and CSV exports.
// Created: 04 Jul 2026

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/domain/models/analytics_models.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CloudAnalyticsRepository {
  final ApiClient _apiClient;
  final EnvironmentConfig _config;

  CloudAnalyticsRepository({
    ApiClient? apiClient,
    EnvironmentConfig? config,
  })  : _apiClient = apiClient ?? ApiClient(),
        _config = config ?? EnvironmentConfig.current;

  /// Fetch core dashboard KPI data
  Future<DashboardMetrics> getDashboard() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/dashboard');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return DashboardMetrics.fromJson(data);
  }

  /// Fetch sales trend data points (daily, weekly, monthly, hourly)
  Future<List<SalesTrendPoint>> getSalesTrend({String period = 'daily'}) async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/sales-trend?period=$period',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => SalesTrendPoint.fromJson(item)).toList();
  }

  /// Fetch top selling products statistics
  Future<List<ProductStat>> getProductStats({String sort = 'revenue'}) async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/products?sort=$sort',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => ProductStat.fromJson(item)).toList();
  }

  /// Fetch critical stock details
  Future<StockAnalytics> getStockStats() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/stock');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return StockAnalytics.fromJson(data);
  }

  /// Fetch financial summaries (debtors, receivables)
  Future<FinanceAnalytics> getFinanceStats() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/finance');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FinanceAnalytics.fromJson(data);
  }

  /// Fetch branches comparison revenue
  Future<List<BranchStat>> getBranchStats() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/branches');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => BranchStat.fromJson(item)).toList();
  }

  /// Fetch staff performance analysis
  Future<List<StaffStat>> getStaffStats() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/staff');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => StaffStat.fromJson(item)).toList();
  }

  /// Export a report as a CSV file and save it locally.
  /// Returns the saved [File] path.
  Future<File> exportReportCsv({required String type}) async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'analytics')}/export?type=$type',
    );
    
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/report-$type-${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(response.body);
    
    debugPrint('[AnalyticsExport] Saved CSV to: ${file.path}');
    return file;
  }
}

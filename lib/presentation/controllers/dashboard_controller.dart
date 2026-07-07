// lib/presentation/controllers/dashboard_controller.dart
// Phase 3 — Dashboard Controller
// Generated: 21 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/dashboard_service.dart';
import 'package:serenutos/providers/repository_providers.dart';

/// Provider for loading the complete dashboard state from the dashboard service
final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final service = await ref.watch(dashboardServiceProvider.future);
  return service.getDashboardData();
});

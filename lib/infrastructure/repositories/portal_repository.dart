// lib/infrastructure/repositories/portal_repository.dart
// Serenut Platform — Portal Repository (Sprint 10)
// Client side interface for dashboard, devices, store nodes and support ticket systems.
// Created: 04 Jul 2026

import 'dart:convert';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class PortalDashboardSummary {
  final int stores;
  final int devices;
  final int activeLicenseCount;
  final int unpaidInvoices;
  final double monthlyRevenue;

  const PortalDashboardSummary({
    required this.stores,
    required this.devices,
    required this.activeLicenseCount,
    required this.unpaidInvoices,
    required this.monthlyRevenue,
  });

  factory PortalDashboardSummary.fromJson(Map<String, dynamic> json) => PortalDashboardSummary(
        stores: json['stores'] as int? ?? 0,
        devices: json['devices'] as int? ?? 0,
        activeLicenseCount: json['activeLicenseCount'] as int? ?? 0,
        unpaidInvoices: json['unpaidInvoices'] as int? ?? 0,
        monthlyRevenue: (json['monthlyRevenue'] as num? ?? 0.0).toDouble(),
      );
}

class PortalDevice {
  final String id;
  final String deviceName;
  final String? storeName;
  final String? lastActiveAt;
  final bool isOnline;

  const PortalDevice({
    required this.id,
    required this.deviceName,
    this.storeName,
    this.lastActiveAt,
    required this.isOnline,
  });

  factory PortalDevice.fromJson(Map<String, dynamic> json) => PortalDevice(
        id: json['id'] as String? ?? '',
        deviceName: json['device_name'] as String? ?? '',
        storeName: json['store_name'] as String?,
        lastActiveAt: json['last_active_at'] as String?,
        isOnline: json['is_online'] as bool? ?? false,
      );
}

class SupportTicket {
  final String id;
  final String title;
  final String description;
  final String priority;
  final String status;
  final String createdAt;

  const SupportTicket({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.createdAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        priority: json['priority'] as String? ?? 'medium',
        status: json['status'] as String? ?? 'open',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class TicketMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final String createdAt;

  const TicketMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.createdAt,
  });

  factory TicketMessage.fromJson(Map<String, dynamic> json) => TicketMessage(
        id: json['id'] as String? ?? '',
        senderId: json['sender_id'] as String? ?? '',
        senderName: json['sender_name'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class PortalRepository {
  final ApiClient _apiClient;
  final EnvironmentConfig _config;

  PortalRepository({
    ApiClient? apiClient,
    EnvironmentConfig? config,
  })  : _apiClient = apiClient ?? ApiClient(),
        _config = config ?? EnvironmentConfig.current;

  /// Fetch dashboard metrics
  Future<PortalDashboardSummary> getDashboard() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'portal')}/dashboard',
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return PortalDashboardSummary.fromJson(data['summary'] as Map<String, dynamic>);
  }

  /// List terminals/devices
  Future<List<PortalDevice>> getDevices() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'portal')}/devices',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => PortalDevice.fromJson(item)).toList();
  }

  /// List support tickets
  Future<List<SupportTicket>> getTickets() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'portal')}/tickets',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => SupportTicket.fromJson(item)).toList();
  }

  /// Get message thread for support ticket
  Future<List<TicketMessage>> getTicketMessages(String ticketId) async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'portal')}/tickets/$ticketId/messages',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => TicketMessage.fromJson(item)).toList();
  }

  /// Reply to a support ticket
  Future<void> replyTicket(String ticketId, String message) async {
    await _apiClient.post(
      '${_config.releaseEndpoint.replaceAll('releases', 'portal')}/tickets/$ticketId/reply',
      {
        'message': message,
      },
    );
  }

  /// Fetch system telemetry health status (CPU, RAM, DB wait lists, Gateway statuses)
  Future<Map<String, dynamic>> getTelemetryHealth() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'telemetry')}/health-status',
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Fetch scopes of audit trail events
  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'telemetry')}/audit-logs',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => Map<String, dynamic>.from(item)).toList();
  }
}

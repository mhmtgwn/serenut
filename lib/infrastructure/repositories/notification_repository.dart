// lib/infrastructure/repositories/notification_repository.dart
// Serenut Platform — Notification & Messaging Repository (Sprint 9)
// Client side interface for templates, balances, campaign orchestration and delivery reports queue.
// Created: 04 Jul 2026

import 'dart:convert';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class NotificationTemplate {
  final String id;
  final String name;
  final String channel;
  final String? title;
  final String body;

  const NotificationTemplate({
    required this.id,
    required this.name,
    required this.channel,
    this.title,
    required this.body,
  });

  factory NotificationTemplate.fromJson(Map<String, dynamic> json) =>
      NotificationTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        channel: json['channel'] as String? ?? 'sms',
        title: json['title'] as String?,
        body: json['body'] as String? ?? '',
      );
}

class QueueEntry {
  final String id;
  final String channel;
  final String recipient;
  final String? title;
  final String body;
  final String status;
  final int retryCount;
  final String? errorMessage;
  final String? deliveredAt;
  final String createdAt;

  const QueueEntry({
    required this.id,
    required this.channel,
    required this.recipient,
    this.title,
    required this.body,
    required this.status,
    required this.retryCount,
    this.errorMessage,
    this.deliveredAt,
    required this.createdAt,
  });

  factory QueueEntry.fromJson(Map<String, dynamic> json) => QueueEntry(
        id: json['id'] as String? ?? '',
        channel: json['channel'] as String? ?? 'sms',
        recipient: json['recipient'] as String? ?? '',
        title: json['title'] as String?,
        body: json['body'] as String? ?? '',
        status: json['status'] as String? ?? 'queued',
        retryCount: json['retry_count'] as int? ?? 0,
        errorMessage: json['error_message'] as String?,
        deliveredAt: json['delivered_at'] as String?,
        createdAt: json['created_at'] as String? ?? '',
      );
}

class CompanyCredits {
  final int smsCredits;
  final int whatsappCredits;
  final int emailCredits;

  const CompanyCredits({
    required this.smsCredits,
    required this.whatsappCredits,
    required this.emailCredits,
  });

  factory CompanyCredits.fromJson(Map<String, dynamic> json) => CompanyCredits(
        smsCredits: json['sms_credits'] as int? ?? 0,
        whatsappCredits: json['whatsapp_credits'] as int? ?? 0,
        emailCredits: json['email_credits'] as int? ?? 0,
      );
}

class NotificationRepository {
  final ApiClient _apiClient;
  final EnvironmentConfig _config;

  NotificationRepository({
    ApiClient? apiClient,
    EnvironmentConfig? config,
  })  : _apiClient = apiClient ?? ApiClient(),
        _config = config ?? EnvironmentConfig.current;

  /// Fetch history of message queue delivery status
  Future<List<QueueEntry>> getQueue() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'notifications')}/queue',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => QueueEntry.fromJson(item)).toList();
  }

  /// Fetch remaining credit balances
  Future<CompanyCredits> getCredits() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'notifications')}/credits',
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CompanyCredits.fromJson(data);
  }

  /// Create or update template details
  Future<void> saveTemplate({
    required String name,
    required String channel,
    String? title,
    required String body,
  }) async {
    await _apiClient.post(
      '${_config.releaseEndpoint.replaceAll('releases', 'notifications')}/templates',
      {
        'name': name,
        'channel': channel,
        'title': title,
        'body': body,
      },
    );
  }

  /// Fetch list of templates
  Future<List<NotificationTemplate>> getTemplates() async {
    final response = await _apiClient.get(
      '${_config.releaseEndpoint.replaceAll('releases', 'notifications')}/templates',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => NotificationTemplate.fromJson(item)).toList();
  }

  /// Trigger bulk campaign queue matching a segment
  Future<int> sendCampaign({
    required String segment,
    required String channel,
    required String templateName,
  }) async {
    final response = await _apiClient.post(
      '${_config.releaseEndpoint.replaceAll('releases', 'notifications')}/campaign',
      {
        'segment': segment,
        'channel': channel,
        'template_name': templateName,
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['queued_count'] as int? ?? 0;
  }
}

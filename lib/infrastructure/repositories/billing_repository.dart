// lib/infrastructure/repositories/billing_repository.dart
// Serenut Platform — Billing & Subscription Repository (Sprint 8)
// Client side interface for plan management, mockup paywall checkout and invoices list.
// Created: 04 Jul 2026

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class BillingPlan {
  final String id;
  final String name;
  final double price;
  final String currency;
  final String billingInterval;
  final Map<String, dynamic> features;

  const BillingPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.billingInterval,
    required this.features,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        price: (json['price'] as num? ?? 0.0).toDouble(),
        currency: json['currency'] as String? ?? 'TRY',
        billingInterval: json['billing_interval'] as String? ?? 'monthly',
        features: json['features'] as Map<String, dynamic>? ?? {},
      );
}

class InvoiceEntry {
  final String id;
  final double amount;
  final String status;
  final String dueAt;
  final String? paidAt;
  final String invoiceNumber;

  const InvoiceEntry({
    required this.id,
    required this.amount,
    required this.status,
    required this.dueAt,
    this.paidAt,
    required this.invoiceNumber,
  });

  factory InvoiceEntry.fromJson(Map<String, dynamic> json) => InvoiceEntry(
        id: json['id'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0.0).toDouble(),
        status: json['status'] as String? ?? 'unpaid',
        dueAt: json['due_at'] as String? ?? '',
        paidAt: json['paid_at'] as String?,
        invoiceNumber: json['invoice_number'] as String? ?? '',
      );
}

class BillingRepository {
  final ApiClient _apiClient;
  final EnvironmentConfig _config;

  BillingRepository({
    ApiClient? apiClient,
    EnvironmentConfig? config,
  })  : _apiClient = apiClient ?? ApiClient(),
        _config = config ?? EnvironmentConfig.current;

  /// Fetch list of subscription tiers
  Future<List<BillingPlan>> getPlans() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'billing')}/plans');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => BillingPlan.fromJson(item)).toList();
  }

  /// Start paywall checkout flow. Returns checkout portal URL.
  Future<String> startSubscription(String planId) async {
    final response = await _apiClient.post(
      '${_config.releaseEndpoint.replaceAll('releases', 'billing')}/subscribe',
      {'plan_id': planId},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['checkoutUrl'] as String;
  }

  /// Fetch history of invoices
  Future<List<InvoiceEntry>> getInvoices() async {
    final response = await _apiClient.get('${_config.releaseEndpoint.replaceAll('releases', 'billing')}/invoices');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => InvoiceEntry.fromJson(item)).toList();
  }

  /// Request auto-renewal cancel at period end
  Future<void> cancelSubscription() async {
    await _apiClient.post('${_config.releaseEndpoint.replaceAll('releases', 'billing')}/cancel', {});
  }
}

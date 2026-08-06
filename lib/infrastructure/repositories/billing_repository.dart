// lib/infrastructure/repositories/billing_repository.dart
// Serenut Platform — Billing & Subscription Repository (Sprint 8)
// Client side interface for plan management, paywall checkout and invoices list.

import 'dart:convert';
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

class CheckoutSession {
  final String invoiceId;
  final String token;
  final String checkoutFormContent;

  const CheckoutSession({
    required this.invoiceId,
    required this.token,
    required this.checkoutFormContent,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> json) =>
      CheckoutSession(
        invoiceId: json['invoiceId'] as String? ?? '',
        token: json['token'] as String? ?? '',
        checkoutFormContent: json['checkoutFormContent'] as String? ?? '',
      );
}

class BillingRepository {
  final ApiClient _apiClient;
  BillingRepository({
    ApiClient? apiClient,
    EnvironmentConfig? config,
  }) : _apiClient = apiClient ?? ApiClient();

  /// Fetch list of subscription tiers
  Future<List<BillingPlan>> getPlans() async {
    final response = await _apiClient.get('/api/v1/billing/plans');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => BillingPlan.fromJson(item)).toList();
  }

  /// Starts a real provider checkout session; callers render the returned
  /// provider form instead of inventing a browser URL.
  Future<CheckoutSession> startSubscription(String planId,
      {String billingPeriod = 'monthly'}) async {
    final response = await _apiClient.post(
      '/api/v1/billing/subscribe',
      {'plan_id': planId, 'billing_period': billingPeriod},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = CheckoutSession.fromJson(data);
    if (session.invoiceId.isEmpty ||
        session.token.isEmpty ||
        session.checkoutFormContent.isEmpty) {
      throw const FormatException('Geçersiz ödeme sağlayıcı oturumu yanıtı.');
    }
    return session;
  }

  /// Fetch history of invoices
  Future<List<InvoiceEntry>> getInvoices() async {
    final response = await _apiClient.get('/api/v1/billing/invoices');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((item) => InvoiceEntry.fromJson(item)).toList();
  }

  /// Request auto-renewal cancel at period end
  Future<void> cancelSubscription() async {
    await _apiClient.post('/api/v1/billing/cancel', {});
  }
}

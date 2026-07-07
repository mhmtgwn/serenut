// lib/presentation/widgets/portal_billing_tab.dart
// Serenut Platform — Portal Billing & Invoices Tab (Sprint 8)
// Displays invoice list and triggers server-side PDF invoice download.
// Created: 04 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/infrastructure/repositories/billing_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/auth_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class PortalBillingTab extends ConsumerStatefulWidget {
  const PortalBillingTab({super.key});

  @override
  ConsumerState<PortalBillingTab> createState() => _PortalBillingTabState();
}

class _PortalBillingTabState extends ConsumerState<PortalBillingTab> {
  bool _isLoading = false;

  Future<void> _downloadInvoicePdf(InvoiceEntry invoice) async {
    setState(() => _isLoading = true);

    try {
      final token = ref.read(authProvider).token;
      if (token == null) throw Exception('Yetkilendirme anahtarı bulunamadı.');

      // In production, we request the PDF stream and share/save it.
      // We will trigger launching the secure download URL directly in browser:
      final uri = Uri.parse(
        'http://185.255.93.94:3000/api/v1/billing/invoices/${invoice.id}/pdf',
      );

      // Add authorization token parameter for query simulation in mockup browser
      final authUri = uri.replace(queryParameters: {'token': token});

      if (await canLaunchUrl(authUri)) {
        await launchUrl(authUri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Fatura PDF bağlantısı açılamadı.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fatura indirme hatası: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final billingRepo = ref.watch(billingRepositoryProvider);

    return FutureBuilder<List<InvoiceEntry>>(
      future: billingRepo.getInvoices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Faturalar yüklenemedi: ${snapshot.error}'));
        }

        final invoices = snapshot.data!;
        if (invoices.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('Kayıtlı fatura bulunamadı.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final inv = invoices[index];
            final due = DateTime.tryParse(inv.dueAt) ?? DateTime.now();

            return Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.receipt_rounded, color: Colors.green, size: 20),
                ),
                title: Text(
                  inv.invoiceNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Vade: ${DateFormat('dd.MM.yyyy').format(due)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${inv.amount.toStringAsFixed(0)} TL',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: inv.status == 'paid' ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        inv.status == 'paid' ? 'Ödendi' : 'Ödenmedi',
                        style: TextStyle(
                          color: inv.status == 'paid' ? Colors.green : Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Colors.blueAccent, size: 20),
                      onPressed: _isLoading ? null : () => _downloadInvoicePdf(inv),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

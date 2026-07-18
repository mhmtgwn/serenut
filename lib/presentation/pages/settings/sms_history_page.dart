// lib/presentation/pages/settings/sms_history_page.dart
// Serenut OS — Cloud Notification & Campaign Hub (Sprint 9)
// Integrated real-time credit checking, campaign wizard and central queue delivery tracking.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/infrastructure/repositories/notification_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';

const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);
const _kBorderColor = Color(0xFFE2E8F0);
const _kBgColor = Color(0xFFF8FAFC);
const _kTextPrimary = Color(0xFF1E293B);
const _kTextSecondary = Color(0xFF64748B);

class SmsHistoryPage extends ConsumerStatefulWidget {
  const SmsHistoryPage({super.key});

  @override
  ConsumerState<SmsHistoryPage> createState() => _SmsHistoryPageState();
}

class _SmsHistoryPageState extends ConsumerState<SmsHistoryPage> {
  String _searchQuery = '';
  String _selectedStatus =
      'all'; // 'all' | 'queued' | 'sent' | 'failed' | 'retrying'
  bool _isActionLoading = false;

  @override
  Widget build(BuildContext context) {
    final notifRepo = ref.watch(notificationRepositoryProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Kampanya & İletişim Hub',
          style: TextStyle(
              color: _kTextPrimary, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kTextPrimary),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: _kBlue),
            tooltip: 'Yeni Kampanya Başlat',
            onPressed: _isActionLoading ? null : _showCampaignWizard,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Credit status bar
          FutureBuilder<CompanyCredits>(
            future: notifRepo.getCredits(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(
                    minHeight: 2, valueColor: AlwaysStoppedAnimation(_kBlue));
              }
              if (snapshot.hasError) return const SizedBox();

              final credits = snapshot.data!;
              return Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildCreditCard(
                          'SMS Kredi',
                          '${credits.smsCredits}',
                          Icons.sms_rounded,
                          Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCreditCard(
                          'WhatsApp',
                          '${credits.whatsappCredits}',
                          Icons.chat_rounded,
                          Colors.teal),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCreditCard(
                          'E-Mail',
                          '${credits.emailCredits}',
                          Icons.mail_rounded,
                          Colors.purple),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1, color: _kBorderColor),

          // 2. Search & filter bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Alıcı veya mesaj ara...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 20, color: _kTextSecondary),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Tümü', 'all'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Kuyrukta', 'queued'),
                      const SizedBox(width: 6),
                      _buildFilterChip('İletildi', 'sent'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Tekrar Deniyor', 'retrying'),
                      const SizedBox(width: 6),
                      _buildFilterChip('Hata', 'failed'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderColor),

          // 3. Queue History list
          Expanded(
            child: FutureBuilder<List<QueueEntry>>(
              future: notifRepo.getQueue(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Kuyruk yüklenemedi: ${snapshot.error}'));
                }

                var list = snapshot.data!;

                // Client-side filtering
                if (_selectedStatus != 'all') {
                  list =
                      list.where((e) => e.status == _selectedStatus).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  list = list
                      .where((e) =>
                          e.recipient.contains(_searchQuery) ||
                          e.body.toLowerCase().contains(_searchQuery))
                      .toList();
                }

                if (list.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_email_unread_rounded,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('Mesaj geçmişi bulunmuyor.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = list[index];
                    final date =
                        DateTime.tryParse(entry.createdAt) ?? DateTime.now();

                    return Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0.5,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _buildChannelIcon(entry.channel),
                                    const SizedBox(width: 8),
                                    Text(entry.recipient,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ],
                                ),
                                _buildStatusBadge(entry.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(entry.body,
                                style: const TextStyle(
                                    fontSize: 12, color: _kTextPrimary)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  DateFormat('dd.MM.yyyy HH:mm').format(date),
                                  style: const TextStyle(
                                      fontSize: 10, color: _kTextSecondary),
                                ),
                                if (entry.errorMessage != null)
                                  Flexible(
                                    child: Text(
                                      'Hata: ${entry.errorMessage}',
                                      style: const TextStyle(
                                          color: _kRed, fontSize: 10),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kTextPrimary)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.white : _kTextSecondary)),
      selected: isSelected,
      selectedColor: _kBlue,
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (selected) {
        if (selected) setState(() => _selectedStatus = value);
      },
    );
  }

  Widget _buildChannelIcon(String channel) {
    IconData icon;
    Color color;

    switch (channel) {
      case 'whatsapp':
        icon = Icons.chat_rounded;
        color = Colors.teal;
        break;
      case 'email':
        icon = Icons.mail_rounded;
        color = Colors.purple;
        break;
      case 'push':
        icon = Icons.notifications_active_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.sms_rounded;
        color = Colors.green;
    }

    return Icon(icon, color: color, size: 18);
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'sent':
        color = _kGreen;
        label = 'İletildi';
        break;
      case 'failed':
        color = _kRed;
        label = 'Hata';
        break;
      case 'retrying':
        color = _kAmber;
        label = 'Tekrar Deniyor';
        break;
      case 'sending':
        color = _kBlue;
        label = 'Gönderiliyor';
        break;
      default:
        color = _kTextSecondary;
        label = 'Kuyrukta';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _showCampaignWizard() async {
    String selectedSegment = 'all_customers';
    String selectedChannel = 'sms';
    String templateName = 'sale_invoice_sms';

    // Seed default template for test simulation convenience
    try {
      final notifRepo = ref.read(notificationRepositoryProvider);
      await notifRepo.saveTemplate(
        name: 'sale_invoice_sms',
        channel: 'sms',
        body:
            'Merhaba {{customer}}, magazamiza gosterdiginiz ilgi icin tesekkur ederiz! {{store}}',
      );
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Toplu Kampanya Sihirbazı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Alıcı Segmenti:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: selectedSegment,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'all_customers',
                          child: Text('Tüm Müşteriler',
                              style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'debtors',
                          child: Text('Veresiye Borcu Olanlar',
                              style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'inactive_30d',
                          child: Text('30 Gündür Alışveriş Yapmayanlar',
                              style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (val) {
                      if (val != null)
                        setDialogState(() => selectedSegment = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Gönderim Kanalı:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: selectedChannel,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'sms',
                          child: Text('SMS', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'whatsapp',
                          child:
                              Text('WhatsApp', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: 'email',
                          child:
                              Text('E-Mail', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (val) {
                      if (val != null)
                        setDialogState(() => selectedChannel = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Kullanılacak Şablon:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: templateName,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'sale_invoice_sms',
                          child: Text('Tanıtım & Teşekkür Şablonu',
                              style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => templateName = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal',
                      style: TextStyle(color: _kTextSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    setState(() => _isActionLoading = true);

                    try {
                      final notifRepo =
                          ref.read(notificationRepositoryProvider);
                      final queuedCount = await notifRepo.sendCampaign(
                        segment: selectedSegment,
                        channel: selectedChannel,
                        templateName: templateName,
                      );

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Kampanya başlatıldı! $queuedCount mesaj kuyruğa eklendi.')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Kampanya tetikleme hatası: $e')),
                        );
                      }
                    } finally {
                      setState(() {
                        _isActionLoading = false;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _kBlue, foregroundColor: Colors.white),
                  child: const Text('Kampanyayı Başlat'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

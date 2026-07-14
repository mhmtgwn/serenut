// lib/presentation/pages/admin/mobile_admin_dashboard.dart
// Serenut POS — Mobile Admin Dashboard Console (Sprint 10)
// Responsive store management panel with KPI metrics, terminal statuses, license tokens and support chats.
// Created: 04 Jul 2026

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/router.dart';
import 'package:serenutos/infrastructure/repositories/portal_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';

const _kBgColor       = Color(0xFFF8FAFC);
const _kCardBg        = Colors.white;
const _kBorderColor   = Color(0xFFE2E8F0);
const _kTextPrimary   = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kGreen         = Color(0xFF10B981);
const _kRed           = Color(0xFFEF4444);
const _kAmber         = Color(0xFFF59E0B);
const _kBlue          = Color(0xFF3B82F6);
const _kPurple        = Color(0xFF8B5CF6);

class MobileAdminDashboard extends ConsumerStatefulWidget {
  const MobileAdminDashboard({super.key});

  @override
  ConsumerState<MobileAdminDashboard> createState() => _MobileAdminDashboardState();
}

class _MobileAdminDashboardState extends ConsumerState<MobileAdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portalRepo = ref.watch(portalRepositoryProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'Mobil Yönetici Paneli',
          style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kTextPrimary),
            onPressed: () => setState(() {}),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kBlue,
          unselectedLabelColor: _kTextSecondary,
          indicatorColor: _kBlue,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded, size: 20), text: 'Özet'),
            Tab(icon: Icon(Icons.devices_rounded, size: 20), text: 'Cihazlar'),
            Tab(icon: Icon(Icons.vpn_key_rounded, size: 20), text: 'Lisanslar'),
            Tab(icon: Icon(Icons.support_agent_rounded, size: 20), text: 'Destek'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(portalRepo),
          _buildDevicesTab(portalRepo),
          _buildLicensesTab(portalRepo),
          _buildTicketsTab(portalRepo),
        ],
      ),
    );
  }

  // ── Tab 1: Summary Dashboard ───────────────────────────────────────────────
  Widget _buildSummaryTab(PortalRepository repo) {
    return FutureBuilder<PortalDashboardSummary>(
      future: repo.getDashboard(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Özet yüklenemedi: ${snapshot.error}'));
        }

        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Genel Mağaza Performansı',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _kTextPrimary),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _buildKpiCard(
                  'Aylık Ciro',
                  NumberFormat.currency(locale: 'tr_TR', symbol: 'TL').format(data.monthlyRevenue),
                  Icons.trending_up_rounded,
                  _kGreen,
                ),
                _buildKpiCard(
                  'Aktif Lisanslar',
                  '${data.activeLicenseCount}',
                  Icons.vpn_key_rounded,
                  _kBlue,
                ),
                _buildKpiCard(
                  'Terminaller',
                  '${data.devices} Cihaz',
                  Icons.devices_rounded,
                  _kPurple,
                ),
                _buildKpiCard(
                  'Borçlu Faturalar',
                  '${data.unpaidInvoices} Fatura',
                  Icons.receipt_long_rounded,
                  _kRed,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildNotificationQuickLinks(),
            const SizedBox(height: 24),
            _buildTelemetrySection(repo),
            const SizedBox(height: 24),
            _buildAuditLogsSection(repo),
          ],
        );
      },
    );
  }

  Widget _buildTelemetrySection(PortalRepository repo) {
    return FutureBuilder<Map<String, dynamic>>(
      future: repo.getTelemetryHealth(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox();
        }
        if (snapshot.hasError) return const SizedBox();

        final data = snapshot.data!;
        final sys = data['system'] ?? {};
        final gw = data['gateways'] ?? {};

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.monitor_heart_rounded, color: _kRed, size: 18),
                  SizedBox(width: 8),
                  Text('Altyapı İzleme & Alarmlar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('RAM Kullanımı: ${sys['memoryUsage'] ?? '0%'}', style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
                  Text('CPU Yükü: ${(sys['cpuLoad'] as num? ?? 0.0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Gateway Durumları:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kTextPrimary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildGatewayIndicator('SMS Gateway', gw['sms'] == 'UP'),
                  _buildGatewayIndicator('Mail Gateway', gw['email'] == 'UP'),
                  _buildGatewayIndicator('WhatsApp', gw['whatsapp'] == 'UP'),
                  _buildGatewayIndicator('FCM Push', gw['push'] == 'UP'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGatewayIndicator(String label, bool isUp) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isUp ? _kGreen : _kRed).withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: (isUp ? _kGreen : _kRed).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: isUp ? _kGreen : _kRed),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isUp ? _kGreen : _kRed)),
        ],
      ),
    );
  }

  Widget _buildAuditLogsSection(PortalRepository repo) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: repo.getAuditLogs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return const SizedBox();

        final logs = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_toggle_off_rounded, color: _kBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Eylem Takip Günlüğü (Audit Log)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary)),
                ],
              ),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                const Text('Eylem kaydı bulunmuyor.', style: TextStyle(fontSize: 11, color: _kTextSecondary))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: logs.length > 5 ? 5 : logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 8, color: _kBorderColor),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final date = DateTime.tryParse(log['created_at'] ?? '') ?? DateTime.now();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${log['user_name']} (${log['action']})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kTextPrimary),
                              ),
                              Text(
                                DateFormat('HH:mm').format(date),
                                style: const TextStyle(fontSize: 9, color: _kTextSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hedef: ${log['entity_type']} (ID: ${log['entity_id']}) | IP: ${log['ip_address']}',
                            style: const TextStyle(fontSize: 9, color: _kTextSecondary),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: _kTextSecondary, fontWeight: FontWeight.w600)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kTextPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationQuickLinks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hızlı İşlemler', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(backgroundColor: Color(0xFFEFF6FF), child: Icon(Icons.campaign_rounded, color: _kBlue, size: 18)),
            title: const Text('Kampanya Yönetim Merkezi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            subtitle: const Text('Müşterilere toplu SMS ve WhatsApp gönderin', style: TextStyle(fontSize: 10)),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () => context.push(AppRoutes.smsHistory),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Devices Observation ─────────────────────────────────────────────
  Widget _buildDevicesTab(PortalRepository repo) {
    return FutureBuilder<List<PortalDevice>>(
      future: repo.getDevices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Cihaz listesi yüklenemedi: ${snapshot.error}'));
        }

        final devices = snapshot.data!;
        if (devices.isEmpty) {
          return const Center(child: Text('Kayıtlı terminal bulunamadı.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: devices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final dev = devices[index];
            return Card(
              color: Colors.white,
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kBorderColor)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: dev.isOnline ? _kGreen.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  child: Icon(Icons.computer_rounded, color: dev.isOnline ? _kGreen : Colors.grey, size: 20),
                ),
                title: Text(dev.deviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Şube: ${dev.storeName ?? "Merkez"}', style: const TextStyle(fontSize: 11)),
                trailing: Text(
                  dev.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(color: dev.isOnline ? _kGreen : _kRed, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Tab 3: Licenses Tab ────────────────────────────────────────────────────
  Widget _buildLicensesTab(PortalRepository repo) {
    // Rely on backend portal summary for list of licenses or directly display packages details
    return FutureBuilder<PortalDashboardSummary>(
      future: repo.getDashboard(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('Lisanslar yüklenemedi: ${snapshot.error}'));

        // For presentation simulation we will query backend active license stats
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kBlue, _kPurple]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lisans Paket Yönetimi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 6),
                  Text('Terminal lisanslarınızı dondurun, yenileyin veya limit ekleyin.', style: TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kBorderColor)),
              child: ListTile(
                leading: const Icon(Icons.vpn_key_rounded, color: _kBlue),
                title: const Text('Pro Lisans Paketi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('Cihaz limiti: 5 terminaller', style: TextStyle(fontSize: 11)),
                trailing: ElevatedButton(
                  onPressed: () => context.push(AppRoutes.paywall),
                  style: ElevatedButton.styleFrom(backgroundColor: _kBlue, foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 10)),
                  child: const Text('Paket Değiştir'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tab 4: Support Tickets ─────────────────────────────────────────────────
  Widget _buildTicketsTab(PortalRepository repo) {
    return FutureBuilder<List<SupportTicket>>(
      future: repo.getTickets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Destek biletleri yüklenemedi: ${snapshot.error}'));
        }

        final tickets = snapshot.data!;
        if (tickets.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.support_agent_rounded, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text('Açık destek talebi bulunmuyor.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tickets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final tkt = tickets[index];
            final date = DateTime.tryParse(tkt.createdAt) ?? DateTime.now();

            return Card(
              color: Colors.white,
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _kBorderColor)),
              child: ListTile(
                title: Text(tkt.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(
                  'Oluşturulma: ${DateFormat('dd.MM.yyyy').format(date)}',
                  style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                ),
                trailing: _buildTicketStatusBadge(tkt.status),
                onTap: () {
                  context.push('${AppRoutes.ticketChat}/${tkt.id}?title=${Uri.encodeComponent(tkt.title)}');
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTicketStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'closed':
        color = Colors.grey;
        label = 'Kapandı';
        break;
      case 'replied':
        color = _kGreen;
        label = 'Yanıtlandı';
        break;
      default:
        color = _kAmber;
        label = 'Açık';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

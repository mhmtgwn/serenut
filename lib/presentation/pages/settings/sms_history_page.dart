import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/infrastructure/repositories/notification_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';

const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kRed = Color(0xFFDC2626);
const _kAmber = Color(0xFFD97706);
const _kBlue = Color(0xFF2563EB);
const _kBorder = Color(0xFFE2E8F0);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);

class SmsHistoryPage extends ConsumerStatefulWidget {
  const SmsHistoryPage({super.key});

  @override
  ConsumerState<SmsHistoryPage> createState() => _SmsHistoryPageState();
}

class _SmsHistoryPageState extends ConsumerState<SmsHistoryPage> {
  String _query = '';
  String _status = 'all';
  late Future<List<QueueEntry>> _history;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _history = ref.read(notificationRepositoryProvider).getQueue();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _history;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SMS Geçmişi',
                style: TextStyle(
                    color: _kText, fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Yerel SIM gönderimleri',
                style: TextStyle(
                    color: _kMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh_rounded, color: _kGreenDark),
          ),
        ],
      ),
      body: FutureBuilder<List<QueueEntry>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _kGreen));
          }
          if (snapshot.hasError) return _errorState(snapshot.error);

          final allSms = (snapshot.data ?? const <QueueEntry>[])
              .where((entry) => entry.channel.toLowerCase() == 'sms')
              .toList();
          final visible = allSms.where(_matchesFilters).toList();

          return RefreshIndicator(
            color: _kGreen,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _summary(allSms)),
                SliverToBoxAdapter(child: _filters()),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(allSms.isEmpty),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => _messageCard(visible[index]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _matchesFilters(QueueEntry entry) {
    final statusMatches = switch (_status) {
      'waiting' => const ['queued', 'pending', 'retrying']
          .contains(entry.status.toLowerCase()),
      'sending' => const ['delivered_to_device', 'sending']
          .contains(entry.status.toLowerCase()),
      'sent' => entry.status.toLowerCase() == 'sent',
      'failed' => entry.status.toLowerCase() == 'failed',
      _ => true,
    };
    if (!statusMatches) return false;
    final query = _query.trim().toLowerCase();
    return query.isEmpty ||
        entry.recipient.toLowerCase().contains(query) ||
        entry.body.toLowerCase().contains(query);
  }

  Widget _summary(List<QueueEntry> entries) {
    int count(Iterable<String> statuses) => entries
        .where((entry) => statuses.contains(entry.status.toLowerCase()))
        .length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              _summaryItem('Bekliyor',
                  count(const ['queued', 'pending', 'retrying']), _kAmber),
              const SizedBox(width: 8),
              _summaryItem('Gönderildi', count(const ['sent']), _kGreen),
              const SizedBox(width: 8),
              _summaryItem('Hata', count(const ['failed']), _kRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                style: const TextStyle(
                    color: _kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    const filters = [
      ('Tümü', 'all'),
      ('Bekliyor', 'waiting'),
      ('Cihazda', 'sending'),
      ('Gönderildi', 'sent'),
      ('Hata', 'failed'),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Telefon veya mesaj ara',
                  prefixIcon: const Icon(Icons.search_rounded, color: _kMuted),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kBorder),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final filter = filters[index];
                    final selected = _status == filter.$2;
                    return ChoiceChip(
                      label: Text(filter.$1),
                      selected: selected,
                      onSelected: (_) => setState(() => _status = filter.$2),
                      selectedColor: _kGreen,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: selected ? _kGreen : _kBorder),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : _kText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageCard(QueueEntry entry) {
    final state = _stateFor(entry.status);
    final createdAt = DateTime.tryParse(entry.createdAt)?.toLocal();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: state.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.sim_card_rounded,
                        color: state.color, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(entry.recipient,
                        style: const TextStyle(
                            color: _kText,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                  _statusBadge(state),
                ],
              ),
              const SizedBox(height: 10),
              Text(entry.body,
                  style: const TextStyle(
                      color: _kText, fontSize: 13, height: 1.4)),
              if (entry.errorMessage?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_friendlyError(entry.errorMessage!),
                      style: const TextStyle(
                          color: _kRed,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.phone_android_rounded,
                      size: 14, color: _kMuted),
                  const SizedBox(width: 5),
                  const Text('Yerel SIM',
                      style: TextStyle(color: _kMuted, fontSize: 11)),
                  const Spacer(),
                  Text(
                    createdAt == null
                        ? 'Tarih yok'
                        : DateFormat('dd.MM.yyyy HH:mm').format(createdAt),
                    style: const TextStyle(color: _kMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(_SmsState state) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: state.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(state.label,
            style: TextStyle(
                color: state.color, fontSize: 10, fontWeight: FontWeight.w800)),
      );

  _SmsState _stateFor(String raw) {
    return switch (raw.toLowerCase()) {
      'sent' => const _SmsState('Gönderildi', _kGreen),
      'failed' => const _SmsState('Hata', _kRed),
      'sending' => const _SmsState('Gönderiliyor', _kBlue),
      'delivered_to_device' => const _SmsState('Cihaza Aktarıldı', _kBlue),
      'retrying' => const _SmsState('Tekrar Deniyor', _kAmber),
      _ => const _SmsState('Bekliyor', _kAmber),
    };
  }

  String _friendlyError(String error) {
    return switch (error) {
      'sms_gateway_timeout' =>
        'SMS cihazı 24 saat içinde mesajı alamadı. Cihazın internetini ve uygulamanın açık olduğunu kontrol edin.',
      'not_primary_sms_gateway' =>
        'Bu cihaz firmanın ana SMS cihazı olarak seçili değil.',
      'sms_gateway_interrupted' =>
        'Cihaz gönderimi tamamlayamadı. Mesaj yeniden gönderim kuyruğuna alındı.',
      _ => error,
    };
  }

  Widget _emptyState(bool noHistory) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sms_outlined, size: 52, color: _kMuted),
              const SizedBox(height: 12),
              Text(noHistory ? 'Henüz SMS kaydı yok' : 'Filtreye uygun SMS yok',
                  style: const TextStyle(
                      color: _kText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(
                noHistory
                    ? 'Yerel SIM üzerinden gönderilen mesajlar burada görünecek.'
                    : 'Aramayı veya durum filtresini değiştirin.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );

  Widget _errorState(Object? error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: _kRed),
              const SizedBox(height: 12),
              const Text('SMS geçmişi yüklenemedi',
                  style: TextStyle(
                      color: _kText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('$error',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kMuted, fontSize: 11)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
}

class _SmsState {
  final String label;
  final Color color;

  const _SmsState(this.label, this.color);
}

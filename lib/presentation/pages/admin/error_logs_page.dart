// lib/presentation/pages/admin/error_logs_page.dart
// Serenut OS — Comprehensive Application Error & Telemetry Logs Viewer
// Phase: Observability & Diagnostics

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

// ── Theme Constants ──────────────────────────────────────────────────────────
const _kBgColor = Color(0xFF0D1117);
const _kCardBg = Color(0xFF161B22);
const _kBorderColor = Color(0xFF30363D);
const _kTextPrimary = Color(0xFFE6EDF3);
const _kTextSecondary = Color(0xFF8B949E);
const _kGreen = Color(0xFF3FB950);
const _kRed = Color(0xFFF85149);
const _kAmber = Color(0xFFD29922);
const _kBlue = Color(0xFF58A6FF);
const _kPurple = Color(0xFFA371F7);

class ErrorLogsPage extends StatefulWidget {
  const ErrorLogsPage({super.key});

  @override
  State<ErrorLogsPage> createState() => _ErrorLogsPageState();
}

class _ErrorLogsPageState extends State<ErrorLogsPage> {
  final _telemetry = TelemetryService();
  StreamSubscription<TelemetryEvent>? _streamSub;

  List<TelemetryEvent> _allEvents = [];
  bool _isLoading = true;
  String _searchQuery = '';
  LogLevel? _selectedLevel; // null = Tümü
  final Set<String> _expandedEventIds = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();

    // Real-time live update subscription
    _streamSub = _telemetry.eventStream.listen((_) {
      if (mounted) {
        _loadLogs(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final events = await _telemetry.getEvents();
      if (mounted) {
        setState(() {
          _allEvents = events;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardBg,
        title: const Text('Logları Temizle', style: TextStyle(color: _kTextPrimary)),
        content: const Text(
          'Tüm yerel hata ve olay kayıtları silinecektir. Devam etmek istiyor musunuz?',
          style: TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Temizle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _telemetry.clearLogs();
      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hata logları başarıyla temizlendi.'),
            backgroundColor: _kGreen,
          ),
        );
      }
    }
  }

  Future<void> _copyAllLogs(List<TelemetryEvent> filtered) async {
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kopyalanacak log kaydı bulunmuyor.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('=== SERENUT OS HATA VE SİSTEM LOG RAPORU ===');
    buffer.writeln('Rapor Tarihi: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Toplam Kayıt: ${filtered.length}\n');

    for (final ev in filtered) {
      buffer.writeln('--------------------------------------------------');
      buffer.writeln('[${ev.level.label}] ${ev.timestamp.toIso8601String()} | CorrId: ${ev.correlationId}');
      buffer.writeln('Olay: ${ev.event}');
      if (ev.errorContext != null) buffer.writeln('Bağlam: ${ev.errorContext}');
      if (ev.errorType != null) buffer.writeln('Hata Türü: ${ev.errorType}');
      if (ev.errorMessage != null) buffer.writeln('Mesaj: ${ev.errorMessage}');
      if (ev.metadata.isNotEmpty) {
        buffer.writeln('Ek Veri: ${ev.metadata}');
      }
      if (ev.stackTrace != null) {
        buffer.writeln('Stack Trace:\n${ev.stackTrace}');
      }
      buffer.writeln('');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${filtered.length} adet log raporu panoya kopyalandı.'),
          backgroundColor: _kBlue,
        ),
      );
    }
  }

  void _copySingleEvent(TelemetryEvent ev) {
    final buffer = StringBuffer();
    buffer.writeln('[${ev.level.label}] ${ev.timestamp.toIso8601String()}');
    buffer.writeln('Olay: ${ev.event}');
    if (ev.errorContext != null) buffer.writeln('Bağlam: ${ev.errorContext}');
    if (ev.errorType != null) buffer.writeln('Hata Türü: ${ev.errorType}');
    if (ev.errorMessage != null) buffer.writeln('Mesaj: ${ev.errorMessage}');
    if (ev.metadata.isNotEmpty) buffer.writeln('Metadata: ${ev.metadata}');
    if (ev.stackTrace != null) buffer.writeln('\nStack Trace:\n${ev.stackTrace}');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hata detayı panoya kopyalandı.'),
        backgroundColor: _kBlue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _triggerTestError() {
    try {
      throw StateError('Manuel Admin Teşhis Testi: Hata log mekanizması başarıyla devrede.');
    } catch (e, st) {
      _telemetry.logError(
        e,
        st,
        context: 'AdminDiagnosticTest',
        level: LogLevel.error,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test hata logu başarıyla üretildi ve kaydedildi.'),
        backgroundColor: _kAmber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allEvents.where((ev) {
      // Level filter
      if (_selectedLevel != null && ev.level != _selectedLevel) {
        return false;
      }
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchEvent = ev.event.toLowerCase().contains(q);
        final matchMsg = ev.errorMessage?.toLowerCase().contains(q) ?? false;
        final matchCtx = ev.errorContext?.toLowerCase().contains(q) ?? false;
        final matchType = ev.errorType?.toLowerCase().contains(q) ?? false;
        return matchEvent || matchMsg || matchCtx || matchType;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kCardBg,
        foregroundColor: _kTextPrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kRed.withValues(alpha: 0.15),
                border: Border.all(color: _kRed.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LOGS',
                style: TextStyle(
                  color: _kRed,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Hata & Sistem Logları',
              style: TextStyle(
                color: _kTextPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded, color: _kTextSecondary),
            onPressed: () => _loadLogs(),
          ),
          IconButton(
            tooltip: 'Tümünü Kopyala',
            icon: const Icon(Icons.copy_all_rounded, color: _kBlue),
            onPressed: () => _copyAllLogs(filtered),
          ),
          IconButton(
            tooltip: 'Logları Temizle',
            icon: const Icon(Icons.delete_sweep_rounded, color: _kRed),
            onPressed: _clearLogs,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: _kTextSecondary),
            color: _kCardBg,
            onSelected: (val) {
              if (val == 'test_error') _triggerTestError();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'test_error',
                child: Row(
                  children: [
                    Icon(Icons.science_outlined, color: _kAmber, size: 18),
                    SizedBox(width: 8),
                    Text('Test Hatası Üret', style: TextStyle(color: _kTextPrimary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search & Filter Controls ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: _kCardBg,
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Hata mesajı, bağlam veya olay ara...',
                    hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: _kTextSecondary, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: _kTextSecondary, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: _kBgColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBlue),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 10),

                // Level Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildLevelChip(null, 'Tümü (${_allEvents.length})'),
                      const SizedBox(width: 8),
                      _buildLevelChip(
                        LogLevel.critical,
                        '🚨 Kritik (${_countByLevel(LogLevel.critical)})',
                        color: _kRed,
                      ),
                      const SizedBox(width: 8),
                      _buildLevelChip(
                        LogLevel.error,
                        '❌ Hata (${_countByLevel(LogLevel.error)})',
                        color: const Color(0xFFF85149),
                      ),
                      const SizedBox(width: 8),
                      _buildLevelChip(
                        LogLevel.warning,
                        '⚠️ Uyarı (${_countByLevel(LogLevel.warning)})',
                        color: _kAmber,
                      ),
                      const SizedBox(width: 8),
                      _buildLevelChip(
                        LogLevel.info,
                        'ℹ️ Bilgi (${_countByLevel(LogLevel.info)})',
                        color: _kBlue,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderColor),

          // ── Events List ───────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _kGreen))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final ev = filtered[index];
                          return _buildEventCard(ev);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  int _countByLevel(LogLevel level) {
    return _allEvents.where((e) => e.level == level).length;
  }

  Widget _buildLevelChip(LogLevel? level, String label, {Color? color}) {
    final isSelected = _selectedLevel == level;
    final effectiveColor = color ?? _kTextPrimary;

    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : _kTextSecondary,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      backgroundColor: _kBgColor,
      selectedColor: effectiveColor.withValues(alpha: 0.35),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected ? effectiveColor : _kBorderColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (_) => setState(() => _selectedLevel = level),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: _kGreen, size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'Herhangi bir hata kaydı bulunmuyor',
              style: TextStyle(color: _kTextPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Arama kriterlerinize uygun log bulunamadı.'
                  : 'Sistem kararlı çalışıyor. Bir hata meydana geldiğinde otomatik olarak burada listelenecektir.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(TelemetryEvent ev) {
    final key = ev.correlationId.isNotEmpty
        ? ev.correlationId
        : '${ev.timestamp.millisecondsSinceEpoch}_${ev.event}';
    final isExpanded = _expandedEventIds.contains(key);

    final levelColor = switch (ev.level) {
      LogLevel.critical => _kRed,
      LogLevel.error => const Color(0xFFF85149),
      LogLevel.warning => _kAmber,
      LogLevel.info => _kBlue,
      LogLevel.debug => _kPurple,
    };

    final hasStackTrace = ev.stackTrace != null && ev.stackTrace!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ev.level == LogLevel.critical
              ? _kRed.withValues(alpha: 0.5)
              : _kBorderColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Severity badge, context chip, timestamp, copy button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: levelColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(ev.level.emoji, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        ev.level.label,
                        style: TextStyle(
                          color: levelColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ev.errorContext != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kBgColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _kBorderColor),
                    ),
                    child: Text(
                      ev.errorContext!,
                      style: const TextStyle(
                        color: _kBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  DateFormat('dd.MM.yyyy HH:mm:ss').format(ev.timestamp),
                  style: const TextStyle(color: _kTextSecondary, fontSize: 11),
                ),
                IconButton(
                  tooltip: 'Kopyala',
                  icon: const Icon(Icons.copy_rounded, size: 16, color: _kTextSecondary),
                  onPressed: () => _copySingleEvent(ev),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Event title
            Text(
              ev.event,
              style: TextStyle(
                color: levelColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),

            // Error Message
            if (ev.errorMessage != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBgColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ev.errorType != null)
                      Text(
                        'Tür: ${ev.errorType!}',
                        style: const TextStyle(
                          color: _kAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      ev.errorMessage!,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Stack Trace section (expandable)
            if (hasStackTrace) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedEventIds.remove(key);
                    } else {
                      _expandedEventIds.add(key);
                    }
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      color: _kTextSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isExpanded ? 'Stack Trace Gizle' : 'Stack Trace Görüntüle',
                      style: const TextStyle(
                        color: _kBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF030712),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: SelectableText(
                    ev.stackTrace!,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

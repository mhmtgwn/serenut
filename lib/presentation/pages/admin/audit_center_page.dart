// lib/presentation/pages/admin/audit_center_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/providers/audit_provider.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/domain/models/permission.dart';

class AuditCenterPage extends ConsumerStatefulWidget {
  const AuditCenterPage({super.key});

  @override
  ConsumerState<AuditCenterPage> createState() => _AuditCenterPageState();
}

class _AuditCenterPageState extends ConsumerState<AuditCenterPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedType = 'Tümü';
  DateTimeRange? _selectedDateRange;
  List<AuditEvent> _events = [];
  bool _isLoading = false;

  final List<String> _eventTypes = [
    'Tümü',
    'product_created',
    'price_changed',
    'product_updated',
    'product_deleted',
    'customer_created',
    'customer_updated',
    'customer_deleted',
    'payment_recorded',
    'sale_created',
    'items_returned',
    'order_created',
    'order_updated',
    'order_deleted',
    'order_status_updated',
    'system_backup',
    'system_restore'
  ];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(auditRepositoryProvider);
      List<AuditEvent> loadedEvents;

      if (_searchQuery.isNotEmpty) {
        loadedEvents = await repo.search(_searchQuery);
      } else {
        loadedEvents = await repo.getEvents(
          eventType: _selectedType == 'Tümü' ? null : _selectedType,
          fromDate: _selectedDateRange?.start,
          toDate: _selectedDateRange?.end.add(const Duration(days: 1)),
        );
      }

      setState(() {
        _events = loadedEvents;
      });
    } catch (_) {
      // Fail-safe
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedType = 'Tümü';
      _selectedDateRange = null;
    });
    _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final hasAccess = currentUser != null &&
        (currentUser.role == UserRole.sysadmin ||
            currentUser.role == UserRole.owner ||
            currentUser.role == UserRole.admin ||
            currentUser.hasPermission(Permission.settingsAudit.value));

    if (!hasAccess) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz bulunmuyor.',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
    }

    const kDarkBackground = Color(0xFF0F172A); // Slate 900
    const kCardBg = Color(0xFF1E293B); // Slate 800
    const kBorderColor = Color(0xFF334155); // Slate 700
    const kAccentColor = Color(0xFF10B981); // Emerald 500
    const kTextSecondary = Color(0xFF94A3B8); // Slate 400

    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        title: const Text(
          'Denetim Merkezi (Audit Center)',
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: kCardBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadEvents,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Panel
          Container(
            padding: const EdgeInsets.all(16),
            color: kCardBg,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText:
                              'Arama yapın (Kullanıcı, varlık, notlar)...',
                          hintStyle: const TextStyle(color: kTextSecondary),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: kTextSecondary),
                          filled: true,
                          fillColor: kDarkBackground,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: kBorderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: kBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: kAccentColor),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (val) {
                          setState(() => _searchQuery = val);
                          _loadEvents();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() => _searchQuery = _searchController.text);
                        _loadEvents();
                      },
                      child: const Text('Ara',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: kDarkBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorderColor),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            dropdownColor: kCardBg,
                            value: _selectedType,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                color: kTextSecondary),
                            items: _eventTypes.map((t) {
                              return DropdownMenuItem<String>(
                                value: t,
                                child: Text(t),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedType = val);
                                _loadEvents();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2025),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            initialDateRange: _selectedDateRange,
                          );
                          if (range != null) {
                            setState(() => _selectedDateRange = range);
                            _loadEvents();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: kDarkBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kBorderColor),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedDateRange == null
                                    ? 'Tarih Aralığı Seçin'
                                    : '${DateFormat('dd.MM.yy').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM.yy').format(_selectedDateRange!.end)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Icon(Icons.calendar_month_rounded,
                                  color: kTextSecondary, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_selectedDateRange != null ||
                        _selectedType != 'Tümü' ||
                        _searchQuery.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          foregroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.clear_all_rounded),
                        onPressed: _clearFilters,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          // Event list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(kAccentColor)))
                : _events.isEmpty
                    ? const Center(
                        child: Text(
                          'Eşleşen denetim kaydı bulunamadı.',
                          style: TextStyle(color: kTextSecondary, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _events.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          return Card(
                            color: kCardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: kBorderColor),
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getEventColor(event.eventType)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: _getEventColor(event.eventType)
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      event.eventType.toUpperCase(),
                                      style: TextStyle(
                                        color: _getEventColor(event.eventType),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    DateFormat('dd.MM.yyyy HH:mm:ss')
                                        .format(event.timestamp),
                                    style: const TextStyle(
                                        color: kTextSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.notes ??
                                          '${event.entityType} mutation',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.person_outline_rounded,
                                            color: kTextSecondary, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          event.userName ?? 'System',
                                          style: const TextStyle(
                                              color: kTextSecondary,
                                              fontSize: 12),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(Icons.devices_rounded,
                                            color: kTextSecondary, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          event.deviceId != null
                                              ? event.deviceId!.substring(0, 8)
                                              : 'unknown',
                                          style: const TextStyle(
                                              color: kTextSecondary,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded,
                                  color: kTextSecondary),
                              onTap: () => _showDetailDialog(event),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Color _getEventColor(String type) {
    if (type.contains('create')) return Colors.greenAccent;
    if (type.contains('delete')) return Colors.redAccent;
    if (type.contains('price') || type.contains('change')) {
      return Colors.orangeAccent;
    }
    if (type.contains('restore')) return Colors.lightBlueAccent;
    return Colors.amberAccent;
  }

  void _showDetailDialog(AuditEvent event) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B), // Slate 800
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155)),
          ),
          title: Text(
            'Detay: ${event.eventType.toUpperCase()}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailField('İşlem ID', event.id),
                _detailField('İşlem Zamanı',
                    DateFormat('dd.MM.yyyy HH:mm:ss').format(event.timestamp)),
                _detailField(
                    'Kullanıcı', '${event.userName} (${event.userId})'),
                _detailField('Varlık Tipi', event.entityType),
                _detailField('Varlık ID', event.entityId ?? '-'),
                _detailField('Cihaz UUID', event.deviceId ?? '-'),
                _detailField('Açıklama/Not', event.notes ?? '-'),
                const Divider(color: Color(0xFF334155), height: 24),
                if (event.oldValue != null) ...[
                  const Text('Eski Değer:',
                      style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(event.oldValue!,
                        style: const TextStyle(
                            color: Colors.redAccent,
                            fontFamily: 'monospace',
                            fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                ],
                if (event.newValue != null) ...[
                  const Text('Yeni Değer:',
                      style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(event.newValue!,
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _detailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}

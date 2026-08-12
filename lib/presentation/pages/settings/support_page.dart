// lib/presentation/pages/settings/support_page.dart
// Serenut OS — Destek Talebi Oluşturma Sayfası

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key});

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  String _category = 'Teknik Sorun';
  String _priority = 'normal'; // low, normal, high, urgent
  bool _isSubmitting = false;

  final _categories = const [
    'Teknik Sorun',
    'Özellik İsteği',
    'Fatura & Lisans',
    'Yazıcı / Donanım',
    'Diğer',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitTicket() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final user = ref.read(currentUserProvider);

      await apiClient.post('/support/tickets', {
        'subject': '[$_category] ${_titleCtrl.text.trim()}',
        'message': _messageCtrl.text.trim(),
        'priority': _priority,
        'category': _category,
        'user_name': user?.name ?? 'Kullanıcı',
        'user_email': user?.email ?? '',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '✅ Destek talebiniz yönetici ekibine iletildi. En kısa sürede dönüş yapılacaktır.'),
            backgroundColor: POSColors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Talebiniz iletilirken hata oluştu: $e'),
            backgroundColor: POSColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: POSColors.card,
        elevation: 0,
        title: Text(
          'Destek Talebi Gönder',
          style: GoogleFonts.inter(
            color: POSColors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: POSColors.greenLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.support_agent_rounded,
                            color: POSColors.green, size: 32),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Serenut OS Teknik Destek',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: POSColors.greenDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Sorunuzu veya talebinizi iletin, sistem yöneticilerimiz hızla yanıtlasın.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: POSColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Kategori Dropdown
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: InputDecoration(
                      labelText: 'Konu Kategorisi *',
                      prefixIcon: const Icon(Icons.category_outlined,
                          color: POSColors.textSecondary, size: 20),
                      filled: true,
                      fillColor: POSColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: POSColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: POSColors.border),
                      ),
                    ),
                    items: _categories
                        .map((cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(cat),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 16),

                  // Öncelik Seviyesi
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: POSColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: POSColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Öncelik Seviyesi',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: POSColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'low', label: Text('Düşük')),
                            ButtonSegment(
                                value: 'normal', label: Text('Normal')),
                            ButtonSegment(value: 'high', label: Text('Yüksek')),
                            ButtonSegment(value: 'urgent', label: Text('Acil')),
                          ],
                          selected: {_priority},
                          onSelectionChanged: (set) {
                            if (set.isNotEmpty) {
                              setState(() => _priority = set.first);
                            }
                          },
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: POSColors.greenLight,
                            selectedForegroundColor: POSColors.greenDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Başlık
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'Konu Başlığı *',
                      hintText: 'Örn: Etiket yazıcı çıktısı hizada değil',
                      prefixIcon: const Icon(Icons.title_rounded,
                          color: POSColors.textSecondary, size: 20),
                      filled: true,
                      fillColor: POSColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: POSColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: POSColors.border),
                      ),
                    ),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? 'Konu başlığı zorunludur'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Mesaj
                  TextFormField(
                    controller: _messageCtrl,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Detaylı Açıklama *',
                      hintText:
                          'Yaşadığınız durumu veya isteğinizi detaylıca açıklayınız…',
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 80),
                        child: Icon(Icons.notes_rounded,
                            color: POSColors.textSecondary, size: 20),
                      ),
                      filled: true,
                      fillColor: POSColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: POSColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: POSColors.border),
                      ),
                    ),
                    validator: (v) {
                      if (v?.trim().isEmpty ?? true) {
                        return 'Açıklama zorunludur';
                      }
                      if (v!.trim().length < 10) {
                        return 'Lütfen sorunu en az 10 karakterle açıklayın';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submitTicket,
                    icon: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Destek Talebini Gönder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: POSColors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

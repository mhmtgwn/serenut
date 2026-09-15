// lib/presentation/pages/settings/widgets/gib_settings_dialog.dart
// Serenut OS — GİB e-Arşiv Portal Giriş Bilgileri Ayar Penceresi

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/providers/gib_invoice_providers.dart';

class GibSettingsDialog extends ConsumerStatefulWidget {
  const GibSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const GibSettingsDialog(),
    );
  }

  @override
  ConsumerState<GibSettingsDialog> createState() => _GibSettingsDialogState();
}

class _GibSettingsDialogState extends ConsumerState<GibSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isTestMode = false;
  double _defaultVatRate = 20.0;
  bool _obscurePassword = true;

  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final creds = ref.read(gibCredentialsProvider);
    _usernameController = TextEditingController(text: creds.username);
    _passwordController = TextEditingController(text: creds.password);
    _isTestMode = creds.isTestMode;
    _defaultVatRate = creds.defaultVatRate;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _testResult = 'Lütfen kullanıcı kodu ve şifre giriniz.';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final service = ref.read(gibInvoiceServiceProvider);
      // Test modunu geçici olarak client'a yansıt
      ref.read(gibEArsivClientProvider).isTestMode = _isTestMode;

      final success = await service.testConnection(
        username: username,
        password: password,
      );

      if (mounted) {
        setState(() {
          _isTesting = false;
          _testSuccess = success;
          _testResult = success
              ? '✅ GİB e-Arşiv Portalına başarıyla bağlanıldı! Oturum açıldı.'
              : '❌ Bağlantı kurulamadı.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testSuccess = false;
          _testResult = '❌ Hata: ${e.toString().replaceAll('Exception:', '')}';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref.read(gibCredentialsProvider.notifier).save(
          username: _usernameController.text,
          password: _passwordController.text,
          isTestMode: _isTestMode,
          defaultVatRate: _defaultVatRate,
        );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GİB e-Arşiv Portal bilgileri kaydedildi.'),
          backgroundColor: POSColors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: POSColors.greenLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: POSColors.greenDark,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GİB e-Arşiv Portal Ayarları',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: POSColors.text,
                              ),
                            ),
                            Text(
                              'Ücretsiz Resmi e-Arşiv Fatura Motoru',
                              style: TextStyle(
                                fontSize: 12,
                                color: POSColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'GİB İnteraktif Vergi Dairesi kullanıcı kodu ve şifrenizi girerek 0 TL maliyetle sınırsız resmi e-Arşiv fatura kesebilirsiniz. Herhangi bir kontör ücreti yoktur.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF1E40AF),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'GİB Kullanıcı Kodu (Kullanıcı Adı)',
                      hintText: 'Örn: 123456 veya TCKN/VKN',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => (val == null || val.trim().isEmpty)
                        ? 'Kullanıcı kodu zorunludur'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'GİB Portal Şifresi',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (val) => (val == null || val.trim().isEmpty)
                        ? 'Şifre zorunludur'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          value: _defaultVatRate,
                          decoration: const InputDecoration(
                            labelText: 'Varsayılan KDV Oranı',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1.0, child: Text('%1 KDV')),
                            DropdownMenuItem(value: 10.0, child: Text('%10 KDV')),
                            DropdownMenuItem(value: 20.0, child: Text('%20 KDV')),
                            DropdownMenuItem(value: 0.0, child: Text('%0 (İstisna)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _defaultVatRate = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Test Modu',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          subtitle: const Text('earsivportaltest',
                              style: TextStyle(fontSize: 10)),
                          value: _isTestMode,
                          activeColor: POSColors.green,
                          onChanged: (val) => setState(() => _isTestMode = val),
                        ),
                      ),
                    ],
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _testSuccess
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _testSuccess
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _testSuccess
                              ? const Color(0xFF166534)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _testConnection,
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.electrical_services_rounded,
                                  size: 18),
                          label: Text(_isTesting ? 'Test Ediliyor...' : 'Bağlantıyı Test Et'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: POSColors.border),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Kaydet'),
                          style: FilledButton.styleFrom(
                            backgroundColor: POSColors.green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
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

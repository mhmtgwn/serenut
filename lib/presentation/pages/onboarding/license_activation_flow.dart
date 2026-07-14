// lib/presentation/pages/onboarding/license_activation_flow.dart
// Serenut OS — Lisans Aktivasyon Akışı
// QR kod tarama (gerçek kamera, mobile_scanner), XXXX-XXXX-XXXX-XXXX formatı

import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/config/theme.dart';

class LicenseActivationFlow extends ConsumerStatefulWidget {
  final void Function(String licenseKey, String licenseType)?
      onLicenseActivated;

  const LicenseActivationFlow({super.key, this.onLicenseActivated});

  @override
  ConsumerState<LicenseActivationFlow> createState() =>
      _LicenseActivationFlowState();
}

class _LicenseActivationFlowState extends ConsumerState<LicenseActivationFlow> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _showScanner = false;
  String? _errorMsg;
  String? _successType; // 'Professional', 'Kurumsal', 'Enterprise'
  DateTime? _expiryDate;
  DateTime? _supportUntil;

  Future<void> _activate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    final rawKey = _ctrl.text.replaceAll('-', '').trim().toUpperCase();

    try {
      final apiClient = ref.read(apiClientProvider);
      final licenseService = ref.read(licenseServiceProvider);
      final deviceId = licenseService.getDeviceUuid();

      final fingerprintService = ref.read(deviceFingerprintServiceProvider);
      final fingerprint = await fingerprintService.getFingerprint();

      // Get device name fallback
      final deviceName = Platform.isAndroid
          ? 'Android POS'
          : (Platform.isWindows ? 'Windows POS' : 'POS Cihazı');

      final response = await apiClient.send(
        'POST',
        '/api/v1/licenses/activate',
        body: {
          'license_key': rawKey,
          'device_id': deviceId,
          'device_name': deviceName,
          'fingerprint': fingerprint.toJson(),
        },
      );

      if (response.isSuccess) {
        final resJson = response.json;
        final licenseInfo = resJson['license_info'] as Map<String, dynamic>;
        final signature = resJson['signature'] as String;

        // Construct canonical client token string by attaching the signature
        // V2 token: uses device_id; V1 legacy: uses allowed_devices
        final Map<String, dynamic> localTokenMap = {
          'merchant_id': licenseInfo['merchant_id'],
          // V2: device_id takes precedence; V1: fall back to allowed_devices
          if (licenseInfo.containsKey('device_id'))
            'device_id': licenseInfo['device_id']
          else
            'allowed_devices': licenseInfo['allowed_devices'],
          'expiry_date': licenseInfo['expiry_date'],
          'tier': licenseInfo['tier'],
          'features': licenseInfo['features'],
          'signature': signature,
          'token_version': licenseInfo['token_version'] ?? 1,
          if (licenseInfo.containsKey('device_token_version'))
            'device_token_version': licenseInfo['device_token_version'],
        };

        final tokenStr = base64.encode(utf8.encode(json.encode(localTokenMap)));
        final saved = await licenseService.saveLicenseToken(tokenStr, rawKey);

        if (saved) {
          licenseService.startHeartbeat(apiClient);
          final tierStr =
              (licenseInfo['tier'] as String? ?? 'BASIC').toUpperCase();
          setState(() {
            _isLoading = false;
            _successType = tierStr;
            _expiryDate = DateTime.parse(licenseInfo['expiry_date'] as String);
            _supportUntil = _expiryDate; // aligned support limit
          });

          if (widget.onLicenseActivated != null) {
            widget.onLicenseActivated!(rawKey, tierStr);
          }
        } else {
          setState(() {
            _isLoading = false;
            _errorMsg =
                'Lisans imza doğrulaması yerelde başarısız oldu. Lütfen sistem yöneticisiyle iletişime geçin.';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMsg =
              'Lisans aktivasyon sunucu hatası. Lütfen anahtarınızı kontrol edin.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMsg = 'Ağ bağlantısı kurulamadı: ${e.toString()}';
      });
    }
  }

  void _onQrDetected(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code != null && code.isNotEmpty) {
      setState(() {
        _showScanner = false;
      });
      // QR içeriğini XXXX-XXXX-XXXX-XXXX formatına dönüştür
      final cleaned = code.replaceAll('-', '').toUpperCase();
      if (cleaned.length == 16) {
        final formatted =
            '${cleaned.substring(0, 4)}-${cleaned.substring(4, 8)}-${cleaned.substring(8, 12)}-${cleaned.substring(12, 16)}';
        _ctrl.text = formatted;
      } else {
        _ctrl.text = code;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showScanner) {
      return _QrScannerView(
        onDetected: _onQrDetected,
        onClose: () => setState(() => _showScanner = false),
      );
    }

    if (_successType != null) {
      return _SuccessView(
        licenseType: _successType!,
        expiryDate: _expiryDate,
        supportUntil: _supportUntil,
        onContinue: () {
          widget.onLicenseActivated?.call(_ctrl.text, _successType!);
          context.go('/onboarding/business');
        },
      );
    }

    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: POSColors.text,
          onPressed: () => context.go('/onboarding'),
        ),
        title: const Text('Lisans Aktivasyonu',
            style:
                TextStyle(fontWeight: FontWeight.w700, color: POSColors.text)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? size.width * 0.2 : 24,
            vertical: 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // İkon
                const Center(
                  child: _LicenseIcon(),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Lisans Anahtarınızı Girin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: POSColors.text),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Satın alma sonrası e-posta ile gönderilen lisans anahtarını girin',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: POSColors.textSecondary),
                ),
                const SizedBox(height: 32),

                // Lisans giriş alanı
                TextFormField(
                  controller: _ctrl,
                  style: const TextStyle(
                      fontSize: 20,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      color: POSColors.text),
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 19, // XXXX-XXXX-XXXX-XXXX = 19 karakter
                  decoration: InputDecoration(
                    labelText: 'Lisans Anahtarı',
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    hintStyle: const TextStyle(
                        letterSpacing: 2, color: POSColors.textDisabled),
                    counterText: '',
                    prefixIcon: const Icon(Icons.vpn_key_rounded,
                        color: POSColors.textSecondary),
                    errorText: _errorMsg,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
                    _LicenseKeyFormatter(),
                  ],
                  validator: (v) {
                    final clean = v?.replaceAll('-', '') ?? '';
                    if (clean.length != 16)
                      return 'Geçerli bir lisans anahtarı girin (XXXX-XXXX-XXXX-XXXX)';
                    return null;
                  },
                  onChanged: (_) {
                    if (_errorMsg != null) setState(() => _errorMsg = null);
                  },
                ),
                const SizedBox(height: 16),

                // QR Kod ile Tara
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showScanner = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: POSColors.text,
                    side: const BorderSide(color: POSColors.border, width: 1.5),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded,
                      size: 20, color: POSColors.textSecondary),
                  label: const Text('QR Kod ile Tara',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 24),

                // Aktifleştir butonu
                FilledButton(
                  onPressed: _isLoading ? null : _activate,
                  style: FilledButton.styleFrom(
                    backgroundColor: POSColors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Aktifleştir',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// XXXX-XXXX-XXXX-XXXX otomatik tire ekleyen formatter
// ─────────────────────────────────────────────────────────────────────────────
class _LicenseKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final clean = newValue.text.replaceAll('-', '').toUpperCase();
    if (clean.isEmpty) return newValue.copyWith(text: '');

    final buffer = StringBuffer();
    for (var i = 0; i < clean.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buffer.write('-');
      buffer.write(clean[i]);
    }
    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR Tarayıcı görünümü (gerçek mobile_scanner)
// ─────────────────────────────────────────────────────────────────────────────
class _QrScannerView extends StatelessWidget {
  final void Function(BarcodeCapture) onDetected;
  final VoidCallback onClose;

  const _QrScannerView({required this.onDetected, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            onDetect: onDetected,
          ),
          // Üst çubuk
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.black54,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Lisans QR Kodunu Kameraya Tutun',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
          // Tarama çerçevesi
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: POSColors.green, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Başarılı aktivasyon görünümü
// ─────────────────────────────────────────────────────────────────────────────
class _SuccessView extends StatelessWidget {
  final String licenseType;
  final DateTime? expiryDate;
  final DateTime? supportUntil;
  final VoidCallback onContinue;

  const _SuccessView({
    required this.licenseType,
    this.expiryDate,
    this.supportUntil,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    String formatDate(DateTime? d) {
      if (d == null) return '—';
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    }

    return Scaffold(
      backgroundColor: POSColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_rounded,
                  size: 80, color: POSColors.green),
              const SizedBox(height: 24),
              const Text('Lisans Aktif!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: POSColors.text)),
              const SizedBox(height: 32),
              _InfoRow(label: 'Lisans Türü', value: licenseType),
              _InfoRow(label: 'Geçerlilik', value: formatDate(expiryDate)),
              _InfoRow(label: 'Destek Süresi', value: formatDate(supportUntil)),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: POSColors.green,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Kuruluma Devam Et',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14, color: POSColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: POSColors.text)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lisans ikonı
// ─────────────────────────────────────────────────────────────────────────────
class _LicenseIcon extends StatelessWidget {
  const _LicenseIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: POSColors.greenLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child:
          const Icon(Icons.vpn_key_rounded, size: 40, color: POSColors.green),
    );
  }
}

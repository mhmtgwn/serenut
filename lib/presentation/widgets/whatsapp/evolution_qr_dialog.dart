// lib/presentation/widgets/whatsapp/evolution_qr_dialog.dart
// Serenut OS — Evolution API QR Bağlantı Dialog'u
//
// Kullanım:
//   await showDialog(
//     context: context,
//     builder: (_) => const EvolutionQRDialog(),
//   );
//
// Davranış:
//   - İlk açılışta sunucudan QR kod ister (GET /api/v1/whatsapp/evolution/qr)
//   - 4 saniyede bir bağlantı durumunu kontrol eder (GET /api/v1/whatsapp/evolution/status)
//   - Bağlantı kurulunca yeşil onay ekranı gösterir ve dialog kapanır
//   - "Bağlantıyı Kes" butonu (POST /api/v1/whatsapp/evolution/disconnect)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

class EvolutionQRDialog extends ConsumerStatefulWidget {
  const EvolutionQRDialog({super.key});

  @override
  ConsumerState<EvolutionQRDialog> createState() => _EvolutionQRDialogState();
}

class _EvolutionQRDialogState extends ConsumerState<EvolutionQRDialog> {
  // Durum makinesi
  _QRState _state = _QRState.loading;
  String? _errorMessage;
  Uint8List? _qrImageBytes;
  String? _connectedPhone;
  String? _connectedName;

  Timer? _statusTimer;
  bool _isDisconnecting = false;

  @override
  void initState() {
    super.initState();
    _loadQR();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  // ── API ÇAĞRILARI ────────────────────────────────────────────────────────────

  Future<void> _loadQR() async {
    setState(() {
      _state = _QRState.loading;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/api/v1/whatsapp/evolution/qr');
      final body = Map<String, dynamic>.from(res.json as Map);

      final qrDataUrl = body['qrcode'] as String?;
      if (qrDataUrl == null || qrDataUrl.isEmpty) {
        throw Exception('Sunucudan QR verisi gelmedi');
      }

      // data:image/png;base64,... → Uint8List
      final base64Part = qrDataUrl.contains(',')
          ? qrDataUrl.split(',').last
          : qrDataUrl;
      final imageBytes = base64Decode(base64Part);

      if (!mounted) return;
      setState(() {
        _qrImageBytes = imageBytes;
        _state = _QRState.waitingForScan;
      });

      // Polling başlat
      _startStatusPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _QRState.error;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    if (!mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/api/v1/whatsapp/evolution/status');
      final body = Map<String, dynamic>.from(res.json as Map);
      final status = body['status'] as String?;

      if (!mounted) return;

      if (status == 'open') {
        _statusTimer?.cancel();
        setState(() {
          _state = _QRState.connected;
          _connectedPhone = body['phone'] as String?;
          _connectedName = body['name'] as String?;
        });
        // Ayarları yenile
        ref.invalidate(settingsNotifierProvider);
        // 2 saniye bekleyip kapat
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (_) {
      // Polling hatası → sessizce devam et
    }
  }

  Future<void> _disconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WhatsApp Bağlantısını Kes'),
        content: const Text('Bağlantı kesilecek ve WhatsApp bildirimleri devre dışı kalacak. Devam etmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: POSColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bağlantıyı Kes'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isDisconnecting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/api/v1/whatsapp/evolution/disconnect', {});
      ref.invalidate(settingsNotifierProvider);
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      if (mounted) {
        setState(() => _isDisconnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: ${_friendlyError(e)}'),
            backgroundColor: POSColors.red,
          ),
        );
      }
    }
  }

  // ── YARDIMCILAR ─────────────────────────────────────────────────────────────

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('timeout') || msg.contains('zaman aşımı')) {
      return 'Sunucu yanıt vermedi. İnternet bağlantınızı kontrol edin.';
    }
    if (msg.contains('202')) {
      return 'QR kodu hazırlanıyor, lütfen birkaç saniye bekleyin…';
    }
    if (msg.contains('503') || msg.contains('evolution')) {
      return 'WhatsApp sunucusuna bağlanılamadı. Sunucu durumunu kontrol edin.';
    }
    return 'Bir hata oluştu. Tekrar deneyin.';
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chat_rounded,
                    color: Color(0xFF25D366),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WhatsApp Bağla',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'QR kodu WhatsApp ile tara',
                        style: TextStyle(
                          color: POSColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                  color: POSColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // İçerik
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _QRState.loading:
        return _buildLoading();
      case _QRState.waitingForScan:
        return _buildQRCode();
      case _QRState.connected:
        return _buildConnected();
      case _QRState.error:
        return _buildError();
    }
  }

  Widget _buildLoading() {
    return const SizedBox(
      key: ValueKey('loading'),
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF25D366)),
            SizedBox(height: 16),
            Text(
              'QR kodu hazırlanıyor…',
              style: TextStyle(color: POSColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQRCode() {
    return Column(
      key: const ValueKey('qr'),
      children: [
        // QR Görüntüsü
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF25D366).withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF25D366).withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _qrImageBytes != null
                ? Image.memory(
                    _qrImageBytes!,
                    fit: BoxFit.contain,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 20),

        // Talimatlar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF25D366).withValues(alpha: 0.2),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Step(number: '1', text: "WhatsApp'ı aç → ⋮ → Bağlı Cihazlar"),
              SizedBox(height: 8),
              _Step(number: '2', text: '"Cihaz Ekle" ye dokun'),
              SizedBox(height: 8),
              _Step(number: '3', text: 'Yukarıdaki QR kodu tara'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Bağlantı bekleniyor göstergesi
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0xFF25D366).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Bağlantı bekleniyor…',
              style: TextStyle(
                color: POSColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Yenile butonu
        TextButton.icon(
          onPressed: _loadQR,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('QR\'ı Yenile'),
          style: TextButton.styleFrom(foregroundColor: POSColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildConnected() {
    return Column(
      key: const ValueKey('connected'),
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF25D366),
            size: 48,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'WhatsApp Bağlandı!',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF16A34A),
          ),
        ),
        if (_connectedPhone != null || _connectedName != null) ...[
          const SizedBox(height: 8),
          Text(
            _connectedName ?? _connectedPhone ?? '',
            style: const TextStyle(
              color: POSColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Müşteri bildirimleri artık WhatsApp üzerinden gidecek.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: POSColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        // Bağlantıyı kes
        if (!_isDisconnecting)
          TextButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off_rounded, size: 16, color: POSColors.red),
            label: const Text(
              'Bağlantıyı Kes',
              style: TextStyle(color: POSColors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      key: const ValueKey('error'),
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.error_outline_rounded, color: POSColors.red, size: 48),
        const SizedBox(height: 12),
        Text(
          _errorMessage ?? 'Bir hata oluştu.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: POSColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _loadQR,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Tekrar Dene'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── YARDIMCI ENUM ────────────────────────────────────────────────────────────

enum _QRState { loading, waitingForScan, connected, error }

// ── ADIM WIDGET'I ─────────────────────────────────────────────────────────────

class _Step extends StatelessWidget {
  final String number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFF25D366),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

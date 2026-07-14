part of '../data_transfer_page.dart';

class ExportProgressDialog extends ConsumerStatefulWidget {
  const ExportProgressDialog({super.key});

  @override
  ConsumerState<ExportProgressDialog> createState() =>
      _ExportProgressDialogState();
}

class _ExportProgressDialogState extends ConsumerState<ExportProgressDialog> {
  double progress = 0.0;
  String statusText = 'Veritabanı okunuyor...';
  bool isDone = false;
  String? errorMessage;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Tarayıcının diyalog kutusunu çizmesi için 150ms süre tanıyoruz.
    Future.delayed(const Duration(milliseconds: 150), _startExport);
  }

  Future<void> _startExport() async {
    if (_started || !mounted) return;
    _started = true;

    try {
      final importer = await ref.read(datasetImportServiceProvider.future);
      final zipBytes = await importer.exportToZip((p) {
        if (mounted) {
          setState(() {
            progress = p;
            if (p < 0.15) {
              statusText = 'Katalog Excel dosyası oluşturuluyor...';
            } else if (p < 0.85) {
              statusText =
                  'Görseller arşivleniyor... (%${(p * 100).toStringAsFixed(0)})';
            } else if (p < 0.95) {
              statusText = 'Arşiv sıkıştırılıyor...';
            } else {
              statusText = 'Tamamlanıyor...';
            }
          });
        }
      });

      if (mounted) {
        setState(() {
          isDone = true;
          progress = 1.0;
          statusText = 'Arşiv başarıyla oluşturuldu!';
        });
      }

      if (mounted) {
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        await FileSaverHelper.saveAndShareFile(
          bytes: zipBytes,
          filename: 'serenut_katalog_$timestamp.zip',
          context: context,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Katalog başarıyla dışarı aktarıldı.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          statusText = 'Hata Oluştu';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        errorMessage != null
            ? 'Dışarı Aktarma Başarısız'
            : (isDone ? 'İşlem Tamamlandı' : 'Dışarı Aktarılıyor...'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage == null && !isDone) ...[
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
            ),
            const SizedBox(height: 16),
            Text(statusText, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              valueColor: const AlwaysStoppedAnimation<Color>(_kGreen),
              backgroundColor: _kBorderColor,
            ),
          ] else if (errorMessage != null) ...[
            const Icon(Icons.error_outline_rounded, color: _kPink, size: 48),
            const SizedBox(height: 16),
            Text(errorMessage!,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center),
          ] else ...[
            const Icon(Icons.check_circle_outline_rounded,
                color: _kGreen, size: 48),
            const SizedBox(height: 16),
            Text(statusText,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ]
        ],
      ),
      actions: [
        if (errorMessage != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat',
                style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── REHBERDEN MÜŞTERİ İÇE AKTARMA EKRANI (PLATFORM DESTEKLİ) ─────────────────
// ══════════════════════════════════════════════════════════════════════════════

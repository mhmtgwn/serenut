part of '../data_transfer_page.dart';

class ImportProgressDialog extends ConsumerStatefulWidget {
  final Uint8List? zipBytes;
  final String? filePath;
  const ImportProgressDialog({this.zipBytes, this.filePath, super.key});

  @override
  ConsumerState<ImportProgressDialog> createState() =>
      _ImportProgressDialogState();
}

class _ImportProgressDialogState extends ConsumerState<ImportProgressDialog> {
  double progress = 0.0;
  String statusText = 'Dosya çözümleniyor...';
  bool isDone = false;
  String? errorMessage;
  Map<String, int>? resultSummary;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Tarayıcının diyalog kutusunu çizmesi için 150ms süre tanıyoruz.
    // Bu sayede donma hissi oluşmaz ve diyalog ilk andan itibaren görünür.
    Future.delayed(const Duration(milliseconds: 150), _startImport);
  }

  Future<void> _startImport() async {
    if (_started || !mounted) return;
    _started = true;

    try {
      Uint8List? bytes = widget.zipBytes;

      if (bytes == null && widget.filePath != null) {
        setState(() {
          statusText = 'Dosya okunuyor...';
        });
        final ioFile = File(widget.filePath!);
        bytes = await ioFile.readAsBytes();
      }

      if (bytes == null) {
        throw Exception('Dosya içeriği okunamadı.');
      }

      final importer = await ref.read(datasetImportServiceProvider.future);
      final result = await importer.importFromZip(bytes, (p, msg) {
        if (mounted) {
          setState(() {
            progress = p;
            statusText = msg;
          });
        }
      });

      if (mounted) {
        setState(() {
          isDone = true;
          progress = 1.0;
          statusText = 'Başarıyla Tamamlandı!';
          resultSummary = result;
        });
      }
      ref.invalidate(productRepositoryProvider);
    } catch (e, stackTrace) {
      debugPrint('❌ CATALOG IMPORT ERROR: $e\n$stackTrace');
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
            ? 'İçe Aktarma Başarısız'
            : (isDone ? 'İçe Aktarma Tamamlandı' : 'İçe Aktarılıyor...'),
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ] else ...[
            const Icon(Icons.check_circle_outline_rounded,
                color: _kGreen, size: 48),
            const SizedBox(height: 16),
            Text(
              'Katalog başarıyla içe aktarıldı!\n\nBaşarılı: ${resultSummary?['success'] ?? 0}\nHatalı: ${resultSummary?['error'] ?? 0}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ]
        ],
      ),
      actions: [
        if (isDone || errorMessage != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat',
                style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

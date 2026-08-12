// lib/presentation/pages/settings/catalog_import_wizard_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:serenutos/providers/dataset_import_provider.dart';
import 'package:serenutos/domain/models/import_strategy.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/infrastructure/services/cloud_catalog_service.dart';
import 'package:serenutos/providers/service_providers.dart';

const _kPrimary = POSColors.green;
const _kBackground = POSColors.surface;
const _kCardBg = POSColors.card;
const _kBorderColor = POSColors.border;
const _kTextMuted = POSColors.textSecondary;
const _kText = POSColors.text;

class CatalogImportWizardPage extends ConsumerStatefulWidget {
  final bool cloudSource;

  const CatalogImportWizardPage({super.key, this.cloudSource = false});

  @override
  ConsumerState<CatalogImportWizardPage> createState() =>
      _CatalogImportWizardPageState();
}

class _CatalogImportWizardPageState
    extends ConsumerState<CatalogImportWizardPage> {
  int _currentStep =
      0; // 0: Select, 1: Analyze, 2: Preview, 3: Import, 4: Results

  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  String? _filePath;
  CloudCatalogService? _cloudCatalogService;
  String? _cloudTemporaryPath;
  bool _isDownloadingCloud = false;
  double _cloudDownloadProgress = 0;
  String _cloudDownloadStatus = 'Bulut kataloğuna bağlanılıyor...';

  bool _isAnalyzing = false;
  double _analyzeProgress = 0.0;
  String _analyzeStatus = 'Hazırlanıyor...';
  Duration _analyzeElapsed = Duration.zero;
  DateTime? _analysisStartedAt;
  Timer? _analysisTicker;

  ParsedCatalogData? _parsedData;
  String? _parseError;

  // Import options (Strategy)
  bool _insertNew = true;
  bool _updateExisting = true;
  bool _syncPrices = true;
  bool _syncStocks = true;
  bool _syncDescriptions = true;
  bool _syncImages = true;
  bool _deactivateMissing = false;
  // Re-importing the same catalogue must be idempotent by default. Matching
  // barcodes update the existing row and replace its stock value; users can
  // still explicitly choose "Mevcut Stoka Ekle" when that is intentional.
  DuplicateResolution _duplicateResolution = DuplicateResolution.update;

  bool _isImporting = false;
  double _importProgress = 0.0;
  String _importStatus = 'Hazırlanıyor...';
  Map<String, int>? _importResult;
  String? _importError;

  @override
  void initState() {
    super.initState();
    if (widget.cloudSource) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _downloadCloudCatalog());
    }
  }

  @override
  void dispose() {
    _analysisTicker?.cancel();
    final path = _cloudTemporaryPath;
    final service = _cloudCatalogService;
    if (path != null && service != null) unawaited(service.cleanup(path));
    super.dispose();
  }

  Future<void> _downloadCloudCatalog() async {
    setState(() {
      _isDownloadingCloud = true;
      _cloudDownloadProgress = 0;
      _cloudDownloadStatus = 'Bulut kataloğuna bağlanılıyor...';
      _parseError = null;
    });
    try {
      final service = createCloudCatalogService(ref.read(apiClientProvider));
      _cloudCatalogService = service;
      final download = await service.download(onProgress: (progress, status) {
        if (!mounted) return;
        setState(() {
          _cloudDownloadProgress = progress;
          _cloudDownloadStatus = status;
        });
      });
      if (!mounted) {
        await service.cleanup(download.path);
        return;
      }
      _cloudTemporaryPath = download.path;
      setState(() {
        _selectedFile = PlatformFile(
          name: 'Serenut-Hazir-Katalog.zip',
          size: download.sizeBytes,
          path: download.path,
        );
        _filePath = download.path;
        _isDownloadingCloud = false;
      });
      await _startAnalysis();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloadingCloud = false;
        _parseError = error.toString().replaceFirst('Exception:', '').trim();
      });
    }
  }

  void _startAnalysisClock() {
    _analysisTicker?.cancel();
    _analysisStartedAt = DateTime.now();
    _analyzeElapsed = Duration.zero;
    _analysisTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _analysisStartedAt == null) return;
      setState(() {
        _analyzeElapsed = DateTime.now().difference(_analysisStartedAt!);
      });
    });
  }

  void _stopAnalysisClock() {
    _analysisTicker?.cancel();
    _analysisTicker = null;
    if (_analysisStartedAt != null) {
      _analyzeElapsed = DateTime.now().difference(_analysisStartedAt!);
    }
  }

  String get _analysisElapsedLabel {
    final minutes = _analyzeElapsed.inMinutes;
    final seconds = _analyzeElapsed.inSeconds.remainder(60);
    return minutes == 0
        ? '$seconds sn'
        : '$minutes dk ${seconds.toString().padLeft(2, '0')} sn';
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'xlsx'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final Uint8List? bytes;
      if (kIsWeb) {
        bytes = file.bytes;
      } else {
        bytes = null;
      }

      setState(() {
        _selectedFile = file;
        _fileBytes = bytes;
        _filePath = file.path;
        _parseError = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Dosya seçilemedi: $e'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _startAnalysis() async {
    if (_fileBytes == null && _filePath == null) return;

    setState(() {
      _currentStep = 1;
      _isAnalyzing = true;
      _analyzeProgress = 0.0;
      _analyzeStatus = 'Dosya yükleniyor...';
      _parseError = null;
    });
    _startAnalysisClock();

    try {
      final importer = await ref.read(datasetImportServiceProvider.future);
      final parsed = kIsWeb
          ? await importer.analyzeZip(_fileBytes!, (progress, status) {
              if (!mounted) return;
              setState(() {
                _analyzeProgress = progress;
                _analyzeStatus = status;
              });
            })
          : await importer.analyzeFile(_filePath!, (progress, status) {
              if (!mounted) return;
              setState(() {
                _analyzeProgress = progress;
                _analyzeStatus = status;
              });
            });

      _stopAnalysisClock();
      if (!mounted) return;
      setState(() {
        _parsedData = parsed;
        _isAnalyzing = false;
        _currentStep = 2;
      });
    } catch (e) {
      _stopAnalysisClock();
      if (!mounted) return;
      setState(() {
        final detail = e.toString().replaceFirst('Exception:', '').trim();
        _parseError = 'İşlem “$_analyzeStatus” aşamasında durdu.\n\n$detail';
        _isAnalyzing = false;
        _currentStep = 0;
      });
    }
  }

  Future<void> _startImport() async {
    if (_fileBytes == null && _filePath == null) return;

    setState(() {
      _currentStep = 3;
      _isImporting = true;
      _importProgress = 0.0;
      _importStatus = 'Veritabanı bağlantısı kuruluyor...';
      _importError = null;
    });

    try {
      final importer = await ref.read(datasetImportServiceProvider.future);
      final strategy = ImportStrategy(
        insertNew: _insertNew,
        updateExisting: _updateExisting,
        deactivateMissing: _deactivateMissing,
        duplicateResolution: _duplicateResolution,
        reactivatePassive: true,
        syncPrices: _syncPrices,
        syncStocks: _syncStocks,
        syncDescriptions: _syncDescriptions,
        syncImages: _syncImages,
      );

      void updateProgress(double progress, String status) {
        setState(() {
          _importProgress = progress;
          _importStatus = status;
        });
      }

      final result = kIsWeb
          ? await importer.importFromZip(
              _fileBytes!,
              updateProgress,
              strategy,
              const {},
              widget.cloudSource,
            )
          : await importer.importFromFile(
              _filePath!,
              updateProgress,
              strategy,
              widget.cloudSource,
            );

      // Clear stale product-list filters and every product projection. Merely
      // rebuilding the repository leaves the paginated controller holding its
      // previous (often empty) page after a reset + catalogue import.
      ref.read(productSearchQueryProvider.notifier).state = '';
      ref.read(productCategoryFilterProvider.notifier).state = null;
      ref.invalidate(productRepositoryProvider);
      ref.invalidate(productsControllerProvider);
      ref.invalidate(salesProductsControllerProvider);
      ref.invalidate(ordersProductsControllerProvider);
      ref.invalidate(productInventorySummaryProvider);
      ref.invalidate(allProductsProvider);
      ref.invalidate(lowStockProductsProvider);
      ProductImage.clearCache();

      setState(() {
        _importResult = result;
        _isImporting = false;
        _currentStep = 4;
      });
    } catch (e) {
      setState(() {
        _importError = e.toString().replaceAll('Exception:', '').trim();
        _isImporting = false;
        _currentStep =
            2; // fall back to preview page so they can retry or check logs
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('Katalog İçe Aktarma Sihirbazı',
            style: TextStyle(color: _kText, fontWeight: FontWeight.bold)),
        backgroundColor: _kCardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kPrimary),
          onPressed: () {
            if (_isAnalyzing || _isImporting) {
              // Prevent leaving mid-process easily
              return;
            }
            context.pop();
          },
        ),
      ),
      body: Column(
        children: [
          _buildStepProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Card(
                    color: _kCardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                      side: const BorderSide(color: _kBorderColor, width: 1),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                      ),
                      child: _buildCurrentStepView(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP PROGRESS INDICATOR ────────────────────────────────────────────────
  Widget _buildStepProgressIndicator() {
    final steps = ['Dosya Seç', 'Çözümle', 'Önizleme', 'Aktar', 'Sonuç'];
    if (MediaQuery.sizeOf(context).width < 600) {
      return Container(
        color: _kCardBg,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Adım ${_currentStep + 1}/${steps.length} · ${steps[_currentStep]}',
                style: const TextStyle(
                  color: _kText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: LinearProgressIndicator(
                value: (_currentStep + 1) / steps.length,
                minHeight: 5,
                borderRadius: BorderRadius.circular(5),
                backgroundColor: POSColors.surfaceMuted,
                valueColor: const AlwaysStoppedAnimation(_kPrimary),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      color: _kCardBg,
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (idx) {
          final isActive = idx == _currentStep;
          final isCompleted = idx < _currentStep;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? _kPrimary
                        : isActive
                            ? _kPrimary
                            : POSColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${idx + 1}',
                            style: TextStyle(
                                color: isActive ? Colors.white : _kTextMuted,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[idx],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive
                          ? _kText
                          : isCompleted
                              ? _kPrimary
                              : _kTextMuted,
                      fontSize: 12,
                      fontWeight: isActive || isCompleted
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (idx < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: Icon(Icons.chevron_right_rounded,
                        color: _kBorderColor, size: 16),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── ROUTE TO CURRENT VIEW ──────────────────────────────────────────────────
  Widget _buildCurrentStepView() {
    if (_parseError != null) {
      return _buildErrorStateView(_parseError!, () {
        if (widget.cloudSource && _filePath == null) {
          _downloadCloudCatalog();
        } else {
          setState(() => _parseError = null);
        }
      });
    }
    if (_importError != null) {
      return _buildErrorStateView(
          _importError!, () => setState(() => _importError = null));
    }

    switch (_currentStep) {
      case 0:
        return _buildStep1FileSelection();
      case 1:
        return _buildStep2Analysis();
      case 2:
        return _buildStep3Preview();
      case 3:
        return _buildStep4ImportProgress();
      case 4:
        return _buildStep5ResultsReport();
      default:
        return _buildStep1FileSelection();
    }
  }

  // ── STATE 1: FILE SELECTION ────────────────────────────────────────────────
  Widget _buildStep1FileSelection() {
    if (_isDownloadingCloud) {
      return Column(
        children: [
          const Icon(Icons.cloud_download_rounded, color: _kPrimary, size: 56),
          const SizedBox(height: 20),
          const Text(
            'Hazır Katalog Buluttan İndiriliyor',
            style: TextStyle(
              color: _kText,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _cloudDownloadStatus,
            style: const TextStyle(color: _kTextMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: _cloudDownloadProgress > 0 ? _cloudDownloadProgress : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: POSColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation(_kPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            _cloudDownloadProgress > 0
                ? '%${(_cloudDownloadProgress * 100).round()}'
                : 'Bağlantı kuruluyor',
            style: const TextStyle(color: _kText, fontWeight: FontWeight.bold),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Katalog Dosyası Seçin',
          style: TextStyle(
              color: _kText, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Ayrıştırma yapmak için ürün bilgilerini içeren bir Excel (.xlsx) veya ürün görselleriyle paketlenmiş bir ZIP (.zip) dosyası yükleyin.',
          style: TextStyle(color: _kTextMuted, fontSize: 13, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // File drop/upload box zone
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              color: POSColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedFile != null ? _kPrimary : _kBorderColor,
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _selectedFile != null
                      ? Icons.insert_drive_file_rounded
                      : Icons.cloud_upload_rounded,
                  color: _kPrimary,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _selectedFile != null
                      ? _selectedFile!.name
                      : 'Tıklayın ve Dosya Seçin',
                  style: const TextStyle(
                      color: _kText, fontSize: 14, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedFile != null
                      ? '${(_selectedFile!.size / (1024 * 1024)).toStringAsFixed(2)} MB'
                      : 'Desteklenen formatlar: .zip, .xlsx',
                  style: const TextStyle(color: _kTextMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),

        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kBorderColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('İptal Et'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _selectedFile != null ? _startAnalysis : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: _kBorderColor,
                  disabledForegroundColor: _kTextMuted,
                ),
                child: const Text('Çözümlemeyi Başlat',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── STATE 2: ANALYSIS PROGRESS ─────────────────────────────────────────────
  Widget _buildStep2Analysis() {
    final phases = <({String label, double threshold})>[
      (label: 'Dosyayı ve arşivi denetle', threshold: 0.02),
      (label: 'Excel ve görselleri bul', threshold: 0.08),
      (label: 'Excel tablosunu aç', threshold: 0.62),
      (label: 'Ürün satırlarını oku', threshold: 0.88),
    ];
    return Column(
      children: [
        const SizedBox(height: 24),
        const SizedBox(
          height: 60,
          width: 60,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kPrimary),
            strokeWidth: 4.5,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Katalog Dosyası Çözümleniyor',
          style: TextStyle(
              color: _kText, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _analyzeStatus,
          style: const TextStyle(color: _kTextMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: _analyzeProgress,
          backgroundColor: POSColors.surfaceMuted,
          valueColor: const AlwaysStoppedAnimation(_kPrimary),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_analyzeProgress * 100).toInt()}% · Geçen süre: $_analysisElapsedLabel',
          style: const TextStyle(
              color: _kText, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 20),
        ...phases.map((phase) {
          final completed = _analyzeProgress >= phase.threshold + 0.14;
          final active = !completed && _analyzeProgress >= phase.threshold;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  completed
                      ? Icons.check_circle_rounded
                      : active
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  color: completed || active ? _kPrimary : _kTextMuted,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  phase.label,
                  style: TextStyle(
                    color: active ? _kText : _kTextMuted,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── STATE 3: PREVIEW / STRATEGY OPTIONS ────────────────────────────────────
  Widget _buildStep3Preview() {
    final productsCount = _parsedData?.products.length ?? 0;
    final imagesCount = _parsedData?.images.length ?? 0;
    final imageWarnings = _parsedData?.imageWarnings ?? 0;

    // Build categories set
    final categories = <String>{};
    for (final p in _parsedData?.products ?? []) {
      if (p['category'] != null) {
        categories.add(p['category']);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Önizleme ve İçe Aktarma Seçenekleri',
          style: TextStyle(
              color: _kText, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Statistics row
        Row(
          children: [
            Expanded(
              child: _buildStatItem('Toplam Ürün', '$productsCount adet',
                  Icons.inventory_2_rounded, Colors.orangeAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem('Paketli Görsel', '$imagesCount adet',
                  Icons.image_rounded, Colors.purpleAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem('Kategoriler', '${categories.length} adet',
                  Icons.category_rounded, _kPrimary),
            ),
          ],
        ),
        const SizedBox(height: 24),

        if (imageWarnings > 0) ...[
          _buildWarningBanner(
            '$imageWarnings bozuk veya desteklenmeyen görsel atlandı. Ürünler yine de içe aktarılabilir.',
          ),
          const SizedBox(height: 16),
        ],

        const Divider(color: _kBorderColor),
        const SizedBox(height: 16),

        // Import Strategy Panel Header
        const Text(
          'İçe Aktarma Stratejisi',
          style: TextStyle(
              color: _kText, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Checklist options
        _buildCheckboxTile(
            'Yeni Ürünleri Ekle',
            'Katalogda bulunup veritabanında olmayan yeni ürünleri kaydeder.',
            _insertNew, (val) {
          setState(() => _insertNew = val ?? true);
        }),
        _buildCheckboxTile(
            'Mevcut Ürünleri Güncelle',
            'Aynı barkoda sahip mevcut ürünleri yeni verilerle günceller.',
            _updateExisting, (val) {
          setState(() => _updateExisting = val ?? true);
        }),

        if (_updateExisting) ...[
          Padding(
            padding: const EdgeInsets.only(left: 32.0, top: 4, bottom: 8),
            child: Column(
              children: [
                _buildSubCheckboxTile('Fiyatları Güncelle', _syncPrices,
                    (val) => setState(() => _syncPrices = val ?? true)),
                _buildSubCheckboxTile('Stok Miktarlarını Güncelle', _syncStocks,
                    (val) => setState(() => _syncStocks = val ?? true)),
                _buildSubCheckboxTile(
                    'Açıklamaları Güncelle',
                    _syncDescriptions,
                    (val) => setState(() => _syncDescriptions = val ?? true)),
                _buildSubCheckboxTile('Görselleri Güncelle', _syncImages,
                    (val) => setState(() => _syncImages = val ?? true)),
              ],
            ),
          ),

          // Duplicate Resolution Radio
          Padding(
            padding: const EdgeInsets.only(left: 32.0, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Eşleşen Ürünlerde Stok Davranışı:',
                    style: TextStyle(color: _kTextMuted, fontSize: 12)),
                Row(
                  children: [
                    Radio<DuplicateResolution>(
                      value: DuplicateResolution.merge,
                      groupValue: _duplicateResolution,
                      activeColor: _kPrimary,
                      onChanged: (val) =>
                          setState(() => _duplicateResolution = val!),
                    ),
                    const Text('Mevcut Stoka Ekle (Topla)',
                        style: TextStyle(color: _kText, fontSize: 13)),
                    const SizedBox(width: 16),
                    Radio<DuplicateResolution>(
                      value: DuplicateResolution.update,
                      groupValue: _duplicateResolution,
                      activeColor: _kPrimary,
                      onChanged: (val) =>
                          setState(() => _duplicateResolution = val!),
                    ),
                    const Text('Yeni Stokla Değiştir (Üzerine Yaz)',
                        style: TextStyle(color: _kText, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ],

        _buildCheckboxTile(
            'Eşleşmeyen Ürünleri Pasifleştir (Riskli!)',
            'Excel listesinde bulunmayan veritabanındaki tüm eski aktif ürünleri pasif hale getirir.',
            _deactivateMissing, (val) {
          setState(() => _deactivateMissing = val ?? false);
        }),

        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep = 0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kBorderColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Geri Git'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _startImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('İçe Aktarmayı Başlat',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── STATE 4: IMPORT PROGRESS ───────────────────────────────────────────────
  Widget _buildStep4ImportProgress() {
    return Column(
      children: [
        const SizedBox(height: 24),
        const SizedBox(
          height: 60,
          width: 60,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kPrimary),
            strokeWidth: 4.5,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Katalog Veritabanına Yazılıyor',
          style: TextStyle(
              color: _kText, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _importStatus,
          style: const TextStyle(color: _kTextMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: _importProgress,
          backgroundColor: POSColors.surfaceMuted,
          valueColor: const AlwaysStoppedAnimation(_kPrimary),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_importProgress * 100).toInt()}%',
          style: const TextStyle(
              color: _kText, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── STATE 5: RESULTS REPORT ────────────────────────────────────────────────
  Widget _buildStep5ResultsReport() {
    final successCount = _importResult?['success'] ?? 0;
    final errorCount = _importResult?['error'] ?? 0;
    final imageErrorCount = _importResult?['imageError'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Icon(
            Icons.verified_rounded,
            color: _kPrimary,
            size: 64,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'İçe Aktarma Tamamlandı!',
          style: TextStyle(
              color: _kText, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Seçilen katalog başarıyla sisteme aktarıldı ve veritabanı kayıtları güncellendi.',
          style: TextStyle(color: _kTextMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        if (imageErrorCount > 0) ...[
          const SizedBox(height: 16),
          _buildWarningBanner(
            '$imageErrorCount bozuk görsel atlandı; kalan ürün ve görseller başarıyla aktarıldı.',
          ),
        ],
        const SizedBox(height: 28),

        // Statistics Box
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: POSColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            children: [
              _buildResultRow(
                  'Başarıyla İşlenen Ürün:', '$successCount adet', _kPrimary),
              const SizedBox(height: 12),
              _buildResultRow('Hatalı / Atlanan Ürün:', '$errorCount adet',
                  errorCount > 0 ? Colors.redAccent : _kTextMuted),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Complete Button
        ElevatedButton(
          onPressed: () => context.pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Sihirbazı Kapat',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // ── STATE UTILS / WIDGET BUILDERS ──────────────────────────────────────────
  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: POSColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: _kTextMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: _kText, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile(String title, String subtitle, bool value,
      ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title,
          style: const TextStyle(
              color: _kText, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: _kTextMuted, fontSize: 12)),
      activeColor: _kPrimary,
      checkColor: Colors.white,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSubCheckboxTile(
      String title, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: _kText, fontSize: 13)),
      activeColor: _kPrimary,
      checkColor: Colors.white,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _kTextMuted, fontSize: 13)),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWarningBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _kText, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStateView(String error, VoidCallback onBack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
            child: Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 56)),
        const SizedBox(height: 16),
        const Text(
          'Bir Hata Oluştu',
          style: TextStyle(
              color: _kText, fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF7F1D1D).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Text(
            error,
            style: const TextStyle(
                color: Colors.redAccent, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: onBack,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Geri Git ve Tekrar Dene'),
        ),
      ],
    );
  }
}

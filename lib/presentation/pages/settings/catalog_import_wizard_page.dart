// lib/presentation/pages/settings/catalog_import_wizard_page.dart
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:serenutos/providers/dataset_import_provider.dart';
import 'package:serenutos/domain/models/import_strategy.dart';
import 'package:serenutos/domain/services/dataset_import_service.dart';
import 'package:serenutos/providers/repository_providers.dart';

const _kPrimary = Color(0xFF10B981); // Emerald Green
const _kBackground = Color(0xFF0F172A); // Slate 900
const _kCardBg = Color(0xFF1E293B); // Slate 800
const _kBorderColor = Color(0xFF334155);
const _kTextMuted = Color(0xFF94A3B8);

class CatalogImportWizardPage extends ConsumerStatefulWidget {
  const CatalogImportWizardPage({super.key});

  @override
  ConsumerState<CatalogImportWizardPage> createState() => _CatalogImportWizardPageState();
}

class _CatalogImportWizardPageState extends ConsumerState<CatalogImportWizardPage> {
  int _currentStep = 0; // 0: Select, 1: Analyze, 2: Preview, 3: Import, 4: Results
  
  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  
  bool _isAnalyzing = false;
  double _analyzeProgress = 0.0;
  String _analyzeStatus = 'Hazırlanıyor...';
  
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
  DuplicateResolution _duplicateResolution = DuplicateResolution.merge;

  bool _isImporting = false;
  double _importProgress = 0.0;
  String _importStatus = 'Hazırlanıyor...';
  Map<String, int>? _importResult;
  String? _importError;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'xlsx'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final Uint8List? bytes;
      if (kIsWeb) {
        bytes = file.bytes;
      } else {
        bytes = await File(file.path!).readAsBytes();
      }

      setState(() {
        _selectedFile = file;
        _fileBytes = bytes;
        _parseError = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya seçilemedi: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _startAnalysis() async {
    if (_fileBytes == null) return;
    
    setState(() {
      _currentStep = 1;
      _isAnalyzing = true;
      _analyzeProgress = 0.0;
      _analyzeStatus = 'Dosya yükleniyor...';
      _parseError = null;
    });

    try {
      final importer = await ref.read(datasetImportServiceProvider.future);
      final parsed = await importer.analyzeZip(_fileBytes!, (progress, status) {
        setState(() {
          _analyzeProgress = progress;
          _analyzeStatus = status;
        });
      });

      setState(() {
        _parsedData = parsed;
        _isAnalyzing = false;
        _currentStep = 2;
      });
    } catch (e) {
      setState(() {
        _parseError = e.toString().replaceAll('Exception:', '').trim();
        _isAnalyzing = false;
        _currentStep = 0;
      });
    }
  }

  Future<void> _startImport() async {
    if (_fileBytes == null) return;

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

      final result = await importer.importFromZip(
        _fileBytes!,
        (progress, status) {
          setState(() {
            _importProgress = progress;
            _importStatus = status;
          });
        },
        strategy,
      );

      // Invalidate the repository so components refresh product list
      ref.invalidate(productRepositoryProvider);

      setState(() {
        _importResult = result;
        _isImporting = false;
        _currentStep = 4;
      });
    } catch (e) {
      setState(() {
        _importError = e.toString().replaceAll('Exception:', '').trim();
        _isImporting = false;
        _currentStep = 2; // fall back to preview page so they can retry or check logs
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        title: const Text('Katalog İçe Aktarma Sihirbazı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _kCardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
              padding: const EdgeInsets.all(24.0),
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
                      padding: const EdgeInsets.all(32.0),
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
                            ? Colors.blueAccent
                            : const Color(0xFF334155),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${idx + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                          ? Colors.white
                          : isCompleted
                              ? _kPrimary
                              : _kTextMuted,
                      fontSize: 12,
                      fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (idx < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: Icon(Icons.chevron_right_rounded, color: _kBorderColor, size: 16),
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
      return _buildErrorStateView(_parseError!, () => setState(() => _parseError = null));
    }
    if (_importError != null) {
      return _buildErrorStateView(_importError!, () => setState(() => _importError = null));
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Katalog Dosyası Seçin',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedFile != null ? _kPrimary : const Color(0xFF475569),
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _selectedFile != null ? Icons.insert_drive_file_rounded : Icons.cloud_upload_rounded,
                  color: _selectedFile != null ? _kPrimary : Colors.blueAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _selectedFile != null ? _selectedFile!.name : 'Tıklayın ve Dosya Seçin',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
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
                  foregroundColor: Colors.white,
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
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: const Color(0xFF334155),
                  disabledForegroundColor: _kTextMuted,
                ),
                child: const Text('Çözümlemeyi Başlat', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── STATE 2: ANALYSIS PROGRESS ─────────────────────────────────────────────
  Widget _buildStep2Analysis() {
    return Column(
      children: [
        const SizedBox(height: 24),
        const SizedBox(
          height: 60,
          width: 60,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
            strokeWidth: 4.5,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Katalog Dosyası Çözümleniyor',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
          backgroundColor: const Color(0xFF0F172A),
          valueColor: const AlwaysStoppedAnimation(_kPrimary),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_analyzeProgress * 100).toInt()}%',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── STATE 3: PREVIEW / STRATEGY OPTIONS ────────────────────────────────────
  Widget _buildStep3Preview() {
    final productsCount = _parsedData?.products.length ?? 0;
    final imagesCount = _parsedData?.images.length ?? 0;

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
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Statistics row
        Row(
          children: [
            Expanded(
              child: _buildStatItem('Toplam Ürün', '$productsCount adet', Icons.inventory_2_rounded, Colors.orangeAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem('Paketli Görsel', '$imagesCount adet', Icons.image_rounded, Colors.purpleAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem('Kategoriler', '${categories.length} adet', Icons.category_rounded, _kPrimary),
            ),
          ],
        ),
        const SizedBox(height: 24),

        const Divider(color: _kBorderColor),
        const SizedBox(height: 16),

        // Import Strategy Panel Header
        const Text(
          'İçe Aktarma Stratejisi',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Checklist options
        _buildCheckboxTile('Yeni Ürünleri Ekle', 'Katalogda bulunup veritabanında olmayan yeni ürünleri kaydeder.', _insertNew, (val) {
          setState(() => _insertNew = val ?? true);
        }),
        _buildCheckboxTile('Mevcut Ürünleri Güncelle', 'Aynı barkoda sahip mevcut ürünleri yeni verilerle günceller.', _updateExisting, (val) {
          setState(() => _updateExisting = val ?? true);
        }),

        if (_updateExisting) ...[
          Padding(
            padding: const EdgeInsets.only(left: 32.0, top: 4, bottom: 8),
            child: Column(
              children: [
                _buildSubCheckboxTile('Fiyatları Güncelle', _syncPrices, (val) => setState(() => _syncPrices = val ?? true)),
                _buildSubCheckboxTile('Stok Miktarlarını Güncelle', _syncStocks, (val) => setState(() => _syncStocks = val ?? true)),
                _buildSubCheckboxTile('Açıklamaları Güncelle', _syncDescriptions, (val) => setState(() => _syncDescriptions = val ?? true)),
                _buildSubCheckboxTile('Görselleri Güncelle', _syncImages, (val) => setState(() => _syncImages = val ?? true)),
              ],
            ),
          ),
          
          // Duplicate Resolution Radio
          Padding(
            padding: const EdgeInsets.only(left: 32.0, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Eşleşen Ürünlerde Stok Davranışı:', style: TextStyle(color: _kTextMuted, fontSize: 12)),
                Row(
                  children: [
                    Radio<DuplicateResolution>(
                      value: DuplicateResolution.merge,
                      groupValue: _duplicateResolution,
                      activeColor: _kPrimary,
                      onChanged: (val) => setState(() => _duplicateResolution = val!),
                    ),
                    const Text('Mevcut Stoka Ekle (Topla)', style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 16),
                    Radio<DuplicateResolution>(
                      value: DuplicateResolution.update,
                      groupValue: _duplicateResolution,
                      activeColor: _kPrimary,
                      onChanged: (val) => setState(() => _duplicateResolution = val!),
                    ),
                    const Text('Yeni Stokla Değiştir (Üzerine Yaz)', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ],

        _buildCheckboxTile('Eşleşmeyen Ürünleri Pasifleştir (Riskli!)', 'Excel listesinde bulunmayan veritabanındaki tüm eski aktif ürünleri pasif hale getirir.', _deactivateMissing, (val) {
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
                  foregroundColor: Colors.white,
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
                child: const Text('İçe Aktarmayı Başlat', style: TextStyle(fontWeight: FontWeight.bold)),
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
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
          backgroundColor: const Color(0xFF0F172A),
          valueColor: const AlwaysStoppedAnimation(_kPrimary),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_importProgress * 100).toInt()}%',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── STATE 5: RESULTS REPORT ────────────────────────────────────────────────
  Widget _buildStep5ResultsReport() {
    final successCount = _importResult?['success'] ?? 0;
    final errorCount = _importResult?['error'] ?? 0;

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
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Seçilen katalog başarıyla sisteme aktarıldı ve veritabanı kayıtları güncellendi.',
          style: TextStyle(color: _kTextMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Statistics Box
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorderColor),
          ),
          child: Column(
            children: [
              _buildResultRow('Başarıyla İşlenen Ürün:', '$successCount adet', _kPrimary),
              const SizedBox(height: 12),
              _buildResultRow('Hatalı / Atlanan Ürün:', '$errorCount adet', errorCount > 0 ? Colors.redAccent : _kTextMuted),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Sihirbazı Kapat', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // ── STATE UTILS / WIDGET BUILDERS ──────────────────────────────────────────
  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: _kTextMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile(String title, String subtitle, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: _kTextMuted, fontSize: 12)),
      activeColor: _kPrimary,
      checkColor: Colors.white,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSubCheckboxTile(String title, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
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
        Text(value, style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildErrorStateView(String error, VoidCallback onBack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 56)),
        const SizedBox(height: 16),
        const Text(
          'Bir Hata Oluştu',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
            style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: onBack,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF334155),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Geri Git ve Tekrar Dene'),
        ),
      ],
    );
  }
}

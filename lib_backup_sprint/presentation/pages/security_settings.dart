import 'package:flutter/material.dart';
import '../../data/datasources/encryption_service.dart';
import '../../shared/utils/error_handler.dart';
import '../widgets/custom_app_bar.dart';

/// Güvenlik ayarları sayfası
class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({Key? key}) : super(key: key);

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final EncryptionService _encryptionService = EncryptionService();
  Map<String, dynamic> _securityStatus = {};
  bool _isLoading = false;
  bool _encryptionEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSecurityStatus();
  }

  /// Güvenlik durumunu yükle
  Future<void> _loadSecurityStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status = await _encryptionService.getSecurityStatus();
      setState(() {
        _securityStatus = status;
        _encryptionEnabled = status['security_enabled'] ?? false;
      });
    } catch (e) {
      ErrorHandler.reportError(
        'Güvenlik Durumu Hatası',
        'Güvenlik durumu yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Şifrelemeyi etkinleştir
  Future<void> _enableEncryption() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Varsayılan şifreleme anahtarı oluştur
      final key = _encryptionService.generateSecureKey();
      final success = await _encryptionService.storeEncryptionKey('default', key);
      
      if (success) {
        // Salt oluştur ve sakla
        final salt = _encryptionService.generateSalt();
        await _encryptionService.storeSalt('default', salt);
        
        ErrorHandler.showSuccess('Şifreleme etkinleştirildi');
        await _loadSecurityStatus();
      }
    } catch (e) {
      ErrorHandler.reportError(
        'Şifreleme Etkinleştirme Hatası',
        'Şifreleme etkinleştirilemedi.',
        details: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Şifrelemeyi devre dışı bırak
  Future<void> _disableEncryption() async {
    final confirmed = await _showDisableConfirmation();
    if (!confirmed) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _encryptionService.clearAllEncryptionKeys();
      if (success) {
        await _loadSecurityStatus();
      }
    } catch (e) {
      ErrorHandler.reportError(
        'Şifreleme Devre Dışı Bırakma Hatası',
        'Şifreleme devre dışı bırakılamadı.',
        details: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Devre dışı bırakma onay dialog'u
  Future<bool> _showDisableConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Şifrelemeyi Devre Dışı Bırak'),
        content: const Text(
          'Bu işlem tüm şifreleme anahtarlarını silecek ve şifreli veriler okunamaz hale gelebilir. '
          'Bu işlem geri alınamaz. Devam etmek istediğinizden emin misiniz?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Devre Dışı Bırak'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Yeni şifreleme anahtarı oluştur
  Future<void> _generateNewKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Şifreleme Anahtarı'),
        content: const Text(
          'Yeni bir şifreleme anahtarı oluşturulacak. '
          'Bu işlem mevcut şifreli verilerin çözülmesini etkileyebilir. '
          'Devam etmek istediğinizden emin misiniz?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final newKey = _encryptionService.generateSecureKey();
        final success = await _encryptionService.storeEncryptionKey('default', newKey);
        
        if (success) {
          ErrorHandler.showSuccess('Yeni şifreleme anahtarı oluşturuldu');
          await _loadSecurityStatus();
        }
      } catch (e) {
        ErrorHandler.reportError(
          'Anahtar Oluşturma Hatası',
          'Yeni şifreleme anahtarı oluşturulamadı.',
          details: e.toString(),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Test verisi şifrele
  Future<void> _testEncryption() async {
    setState(() {
      _isLoading = true;
    });

    try {
      const testData = 'Bu bir test verisidir. 🔒';
      const testKey = 'test_data';
      
      // Veriyi şifrele ve sakla
      final encryptSuccess = await _encryptionService.encryptAndStore(testKey, testData);
      
      if (encryptSuccess) {
        // Veriyi geri al ve çöz
        final decryptedData = await _encryptionService.decryptAndRetrieve(testKey);
        
        if (decryptedData == testData) {
          ErrorHandler.showSuccess('Şifreleme testi başarılı! ✅');
          
          // Test verisini temizle
          await _encryptionService.deleteEncryptedData(testKey);
        } else {
          ErrorHandler.reportError(
            'Şifreleme Test Hatası',
            'Şifreli veri doğru çözülemedi.',
          );
        }
      }
    } catch (e) {
      ErrorHandler.reportError(
        'Şifreleme Test Hatası',
        'Şifreleme testi sırasında bir sorun oluştu.',
        details: e.toString(),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Güvenlik Ayarları',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Güvenlik durumu
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _encryptionEnabled ? Icons.security : Icons.security_outlined,
                                color: _encryptionEnabled ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Güvenlik Durumu',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          _buildStatusItem(
                            'Şifreleme',
                            _encryptionEnabled ? 'Etkin' : 'Devre Dışı',
                            _encryptionEnabled ? Colors.green : Colors.red,
                          ),
                          
                          _buildStatusItem(
                            'Şifreleme Anahtarları',
                            '${_securityStatus['encryption_keys'] ?? 0}',
                            Colors.blue,
                          ),
                          
                          _buildStatusItem(
                            'Salt Değerleri',
                            '${_securityStatus['salts'] ?? 0}',
                            Colors.purple,
                          ),
                          
                          _buildStatusItem(
                            'Şifreli Veri Sayısı',
                            '${_securityStatus['encrypted_data_count'] ?? 0}',
                            Colors.orange,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Şifreleme kontrolü
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.vpn_key,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Şifreleme Yönetimi',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          if (!_encryptionEnabled)
                            Column(
                              children: [
                                const Text(
                                  'Hassas verilerinizi korumak için şifrelemeyi etkinleştirin. '
                                  'Bu özellik müşteri bilgileri ve ödeme verilerini güvenli hale getirir.',
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _enableEncryption,
                                    icon: const Icon(Icons.security),
                                    label: const Text('Şifrelemeyi Etkinleştir'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                const Text(
                                  'Şifreleme etkin. Hassas verileriniz güvenli şekilde korunuyor.',
                                ),
                                const SizedBox(height: 16),
                                
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _generateNewKey,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Yeni Anahtar'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _testEncryption,
                                        icon: const Icon(Icons.bug_report),
                                        label: const Text('Test Et'),
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 8),
                                
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _disableEncryption,
                                    icon: const Icon(Icons.security_outlined),
                                    label: const Text('Şifrelemeyi Devre Dışı Bırak'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Güvenlik önerileri
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Güvenlik Önerileri',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          _buildRecommendationItem(
                            '🔒 Şifrelemeyi etkin tutun',
                            'Hassas verilerinizi korumak için şifrelemeyi her zaman etkin tutun.',
                          ),
                          
                          _buildRecommendationItem(
                            '💾 Düzenli yedekleme yapın',
                            'Verilerinizi güvenli bir yerde düzenli olarak yedekleyin.',
                          ),
                          
                          _buildRecommendationItem(
                            '🔄 Anahtarları güncelleyin',
                            'Güvenlik anahtarlarınızı düzenli aralıklarla yenileyin.',
                          ),
                          
                          _buildRecommendationItem(
                            '📱 Cihazınızı koruyun',
                            'Cihazınızda ekran kilidi ve güvenlik önlemleri kullanın.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Durum öğesi oluştur
  Widget _buildStatusItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Öneri öğesi oluştur
  Widget _buildRecommendationItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

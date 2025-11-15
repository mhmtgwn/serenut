import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../data/datasources/business_profile_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final BusinessProfileService _profileService = BusinessProfileService.instance;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isEditing = false;
  final ImagePicker _picker = ImagePicker();

  // Form controller'ları
  final _companyNameController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _noteController = TextEditingController();
  final _currencyController = TextEditingController();
  String? _logoPath;

  // Şifre değiştirme için
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _storeNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _taxNumberController.dispose();
    _noteController.dispose();
    _currencyController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await _profileService.getBusinessProfile();
      
      setState(() {
        _companyNameController.text = profile['company_name'] ?? '';
        _storeNameController.text = profile['store_name'] ?? '';
        _phoneController.text = profile['phone'] ?? '';
        _addressController.text = profile['address'] ?? '';
        _emailController.text = profile['email'] ?? '';
        _taxNumberController.text = profile['tax_number'] ?? '';
        _noteController.text = profile['note'] ?? '';
        _currencyController.text = profile['currency'] ?? '₺ TL';
        _logoPath = profile['logo_path'];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profil bilgileri yüklenirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Klavyeyi kapat
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _saveProfileData() async {
    _dismissKeyboard();
    
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _profileService.updateProfile(
        companyName: _companyNameController.text,
        storeName: _storeNameController.text,
        phone: _phoneController.text,
        address: _addressController.text,
        email: _emailController.text,
        taxNumber: _taxNumberController.text,
        note: _noteController.text,
        currency: _currencyController.text,
        logoPath: _logoPath,
      );

      if (mounted) {
        if (result) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profil başarıyla güncellendi'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _isEditing = false;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profil güncellenirken hata oluştu'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profil kaydedilirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      // Logo seçim kaynağını sor
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Logo Seçimi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galeriden Seç'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Kamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
          ],
        ),
      );
      
      if (source == null) return;
      
      // Klavyeyi kapat
      FocusScope.of(context).unfocus();
      
      // Yükleniyor göster
      setState(() {
        _isLoading = true;
      });
      
      final XFile? pickedImage = await _picker.pickImage(
        source: source,
        imageQuality: 80, // Daha hızlı yükleme ve daha küçük boyut için
        maxWidth: 800,
        maxHeight: 600,
      );
      
      if (pickedImage == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Dosyayı uygulama dizinine kopyala
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = DateTime.now().millisecondsSinceEpoch.toString() + 
          '_' + path.basename(pickedImage.path);
      final String newPath = path.join(appDir.path, 'logos', fileName);
      
      // Klasör yoksa oluştur
      final Directory logosDir = Directory(path.join(appDir.path, 'logos'));
      if (!await logosDir.exists()) {
        await logosDir.create(recursive: true);
      }
      
      // Dosyayı kopyala
      final File imageFile = File(pickedImage.path);
      await imageFile.copy(newPath);
      
      if (mounted) {
        setState(() {
          _logoPath = newPath;
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo başarıyla yüklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resim seçilirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPasswordChangeDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Şifre Değiştir'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _currentPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Mevcut Şifre',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCurrentPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setStateDialog(() {
                          _obscureCurrentPassword = !_obscureCurrentPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureCurrentPassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifre',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setStateDialog(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureNewPassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifre (Tekrar)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setStateDialog(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => _changePassword(),
              child: const Text('Değiştir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    // Şifre kontrolü
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yeni şifreler eşleşmiyor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_newPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yeni şifre boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final result = await _profileService.changePassword(
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      if (result) {
        Navigator.of(context).pop(); // Dialog'u kapat
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şifre başarıyla değiştirildi'),
            backgroundColor: Colors.green,
          ),
        );

        // Controller'ları temizle
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mevcut şifre yanlış'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Şifre değiştirme hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProfileImage() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Responsif logo konteynerı
          LayoutBuilder(
            builder: (context, constraints) {
              // Ekran genişliğine göre logo boyutu ayarlanıyor
              final screenWidth = MediaQuery.of(context).size.width;
              final logoWidth = screenWidth < 600 ? screenWidth * 0.5 : 300.0;
              
              return Column(
                children: [
                  Container(
                    width: logoWidth,
                    height: logoWidth * 0.6, // 3:5 aspect ratio
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      border: Border.all(color: Colors.grey.withAlpha(77), width: 1),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(26),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _logoPath != null
                          ? Image(
                              image: ResizeImage(
                                FileImage(File(_logoPath!)),
                                width: 400,
                                height: 240,
                              ),
                              fit: BoxFit.contain,
                            )
                          : Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                  if (_isEditing) 
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Logo Seç'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Resim boyutu: En az 200x200 piksel önerilir',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileImage(),
          const SizedBox(height: 24),
          
          // İşletme/Şirket Adı
          TextFormField(
            controller: _companyNameController,
            decoration: const InputDecoration(
              labelText: 'İşletme/Şirket Adı',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business),
            ),
            enabled: _isEditing,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'İşletme adı boş olamaz';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Mağaza Adı
          TextFormField(
            controller: _storeNameController,
            decoration: const InputDecoration(
              labelText: 'Mağaza Adı',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.store),
            ),
            enabled: _isEditing,
          ),
          const SizedBox(height: 16),
          
          // Telefon
          TextFormField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Telefon',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
            ),
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          
          // E-posta
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'E-posta',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            enabled: _isEditing,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                // Basit e-posta doğrulama
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Geçerli bir e-posta adresi girin';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Adres
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Adres',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on),
            ),
            enabled: _isEditing,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          
          // Vergi Numarası
          TextFormField(
            controller: _taxNumberController,
            decoration: const InputDecoration(
              labelText: 'Vergi Numarası',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance),
            ),
            enabled: _isEditing,
          ),
          const SizedBox(height: 16),
          
          // Para Birimi
          TextFormField(
            controller: _currencyController,
            decoration: const InputDecoration(
              labelText: 'Para Birimi',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.currency_exchange),
            ),
            enabled: _isEditing,
          ),
          const SizedBox(height: 16),
          
          // Fiş Notu
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Fiş Notu',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note),
            ),
            enabled: _isEditing,
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          
          if (!_isEditing)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _showPasswordChangeDialog,
                  icon: const Icon(Icons.lock),
                  label: const Text('Şifre Değiştir'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditing = true;
                    });
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Düzenle'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          
          if (_isEditing)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditing = false;
                      _loadProfileData(); // Değişiklikleri iptal et
                    });
                  },
                  icon: const Icon(Icons.cancel),
                  label: const Text('İptal'),
                ),
                ElevatedButton.icon(
                  onPressed: _saveProfileData,
                  icon: const Icon(Icons.save),
                  label: const Text('Kaydet'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: _dismissKeyboard, // Klavyeyi kapat
      child: Scaffold(
        backgroundColor: isDarkMode 
            ? const Color(0xFF1C1C1E) 
            : const Color(0xFFF2F2F7),
        appBar: AppBar(
          title: const Text('İşletme Profili'),
          centerTitle: false,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // AppBar yeterli olduğu için başlık kaldırıldı
                    // Form kartı
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(13),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildForm(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
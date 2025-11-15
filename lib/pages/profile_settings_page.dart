import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _companyTaxController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyRegistrationController = TextEditingController();
  final _companyWebsiteController = TextEditingController();
  final _userNameController = TextEditingController();
  final _userPhoneController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _isLoading = true;
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _companyPhoneController.dispose();
    _companyAddressController.dispose();
    _companyTaxController.dispose();
    _companyEmailController.dispose();
    _companyRegistrationController.dispose();
    _companyWebsiteController.dispose();
    _userNameController.dispose();
    _userPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _companyNameController.text = prefs.getString('company_name') ?? '';
      _companyPhoneController.text = prefs.getString('company_phone') ?? '';
      _companyAddressController.text = prefs.getString('company_address') ?? '';
      _companyTaxController.text = prefs.getString('company_tax') ?? '';
      _companyEmailController.text = prefs.getString('company_email') ?? '';
      _companyRegistrationController.text =
          prefs.getString('company_registration') ?? '';
      _companyWebsiteController.text = prefs.getString('company_website') ?? '';
      _userNameController.text = prefs.getString('user_name') ?? '';
      _userPhoneController.text = prefs.getString('user_phone') ?? '';
      _logoPath = prefs.getString('company_logo');
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_name', _companyNameController.text);
    await prefs.setString('company_phone', _companyPhoneController.text);
    await prefs.setString('company_address', _companyAddressController.text);
    await prefs.setString('company_tax', _companyTaxController.text);
    await prefs.setString('company_email', _companyEmailController.text);
    await prefs.setString(
        'company_registration', _companyRegistrationController.text);
    await prefs.setString('company_website', _companyWebsiteController.text);
    await prefs.setString('user_name', _userNameController.text);
    await prefs.setString('user_phone', _userPhoneController.text);
    if (_logoPath != null) {
      await prefs.setString('company_logo', _logoPath!);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil bilgileri kaydedildi'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() => _logoPath = image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logo seçilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeLogo() async {
    setState(() => _logoPath = null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('company_logo');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Ayarları'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded),
            onPressed: _saveSettings,
            tooltip: 'Kaydet',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Logo Seçimi
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text(
                            'Şirket Logosu',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _pickLogo,
                            child: Container(
                              width: _logoPath != null ? double.infinity : 150,
                              height: _logoPath != null ? 200 : 150,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF10B981),
                                  width: 2,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: _logoPath != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Image.file(
                                        File(_logoPath!),
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate_rounded,
                                          size: 48,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Logo Seç',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          if (_logoPath != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _removeLogo,
                              icon: const Icon(Icons.delete_rounded),
                              label: const Text('Logoyu Kaldır'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Şirket Bilgileri
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _companyNameController,
                            decoration: InputDecoration(
                              labelText: 'Şirket Adı',
                              prefixIcon: const Icon(Icons.business_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Şirket adı gerekli';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyPhoneController,
                            decoration: InputDecoration(
                              labelText: 'Telefon',
                              prefixIcon: const Icon(Icons.phone_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyEmailController,
                            decoration: InputDecoration(
                              labelText: 'E-posta',
                              prefixIcon: const Icon(Icons.email_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyTaxController,
                            decoration: InputDecoration(
                              labelText: 'Vergi No',
                              prefixIcon:
                                  const Icon(Icons.receipt_long_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyRegistrationController,
                            decoration: InputDecoration(
                              labelText: 'Kayıt No / Ticaret Sicil No',
                              prefixIcon: const Icon(Icons.badge_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyWebsiteController,
                            decoration: InputDecoration(
                              labelText: 'Web Sitesi',
                              prefixIcon: const Icon(Icons.language_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _companyAddressController,
                            decoration: InputDecoration(
                              labelText: 'Adres',
                              prefixIcon: const Icon(Icons.location_on_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Kullanıcı Bilgileri
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF3B82F6).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.person_rounded,
                                    size: 20, color: Color(0xFF3B82F6)),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Kullanıcı Bilgileri',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _userNameController,
                            decoration: InputDecoration(
                              labelText: 'Adınız Soyadınız',
                              prefixIcon:
                                  const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              helperText: 'Siparişlerde görünecek',
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Adınız gerekli';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _userPhoneController,
                            decoration: InputDecoration(
                              labelText: 'Telefon Numaranız',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              helperText: 'İletişim için kullanılacak',
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text(
                          'Kaydet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

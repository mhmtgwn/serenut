import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_provider.dart';
import '../theme/app_theme.dart';
import '../modules/devices.dart';
import '../settings/receipt_label_designer.dart';
import 'profile_settings.dart';

/// Uygulama ayarları sayfası.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Ayarlar
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _smsNotificationsEnabled = false;
  String _selectedLanguage = 'Türkçe';
  String _selectedCurrency = '₺';
  String _businessName = 'SHAMAN İŞLETMESİ';
  String _address = '';
  String _phone = '0212 123 45 67';
  String _taxInfo = 'Vergi No: 1234567890';
  String _footerNote = 'Bizi tercih ettiğiniz için teşekkür ederiz!';
  String? _logoPath;
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Genel ayarları yükle
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _soundEnabled = prefs.getBool('sound_enabled') ?? true;
        _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
        _smsNotificationsEnabled = prefs.getBool('sms_notifications_enabled') ?? false;
        _selectedLanguage = prefs.getString('selected_language') ?? 'Türkçe';
        _selectedCurrency = prefs.getString('selected_currency') ?? '₺';
        
        // İşletme bilgilerini yükle
        _businessName = prefs.getString('business_name') ?? 'SHAMAN İŞLETMESİ';
        _address = prefs.getString('address') ?? '';
        _phone = prefs.getString('phone') ?? '0212 123 45 67';
        _taxInfo = prefs.getString('tax_info') ?? 'Vergi No: 1234567890';
        _footerNote = prefs.getString('footer_note') ?? 'Bizi tercih ettiğiniz için teşekkür ederiz!';
        _logoPath = prefs.getString('logo_path');
      });
      
    } catch (e) {
      debugPrint('Ayarlar yüklenirken hata: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setBool('notifications_enabled', _notificationsEnabled);
      await prefs.setBool('sound_enabled', _soundEnabled);
      await prefs.setBool('vibration_enabled', _vibrationEnabled);
      await prefs.setString('selected_language', _selectedLanguage);
      await prefs.setString('selected_currency', _selectedCurrency);
      await prefs.setBool('sms_notifications_enabled', _smsNotificationsEnabled);
      
      await prefs.setString('business_name', _businessName);
      await prefs.setString('address', _address);
      await prefs.setString('phone', _phone);
      await prefs.setString('tax_info', _taxInfo);
      await prefs.setString('footer_note', _footerNote);
      if (_logoPath != null) {
        await prefs.setString('logo_path', _logoPath!);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // iOS tarzı ayarlar kartı widget'ı (başlık olmadan)
  Widget _buildSettingsCard({
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: children,
          ),
        ),
      ),
    );
  }

  // iOS tarzı ayarlar öğesi
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool showDivider = true,
  }) {
    // Tema renklerini kullanıyoruz
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final iconBgColor = AppTheme.greenColor; // Tema yeşil rengini kullanıyoruz
    final iconColor = isDarkMode ? AppTheme.darkTextColor : AppTheme.lightTextColor; // Tema metin rengini kullanıyoruz
// Tema sınır rengini kullanıyoruz
// Tema kart rengini kullanıyoruz
    
    return Column(
      children: [
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: subtitle != null ? Text(subtitle) : null,
          trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
          onTap: onTap,
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 70,
            endIndent: 0,
            color: Colors.grey.withAlpha(51),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final themeText = themeProvider.isDarkMode ? 'Karanlık Tema' : 'Aydınlık Tema';
    
    // Tema renklerini tanımlıyoruz
    final iconBgColor = AppTheme.greenColor;
    final inactiveTrackColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final inactiveThumbColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    
    return Scaffold(
      backgroundColor: isDarkMode 
          ? const Color(0xFF1C1C1E) 
          : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Ayarlar'),
        centerTitle: false,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 8),
                
                // İşletme Profili
                _buildSettingsCard(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.business,
                      title: 'İşletme Profili',
                      subtitle: 'İşletme bilgilerini yönet',
                      onTap: () {
                        Navigator.pushNamed(context, '/profile-settings');
                      },
                      showDivider: false,
                    ),
                  ],
                ),
                
                // İşletme Ayarları
                _buildSettingsCard(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.receipt_outlined,
                      title: 'Fiş ve Etiket Tasarımı',
                      subtitle: 'Fiş ve etiket formatını düzenle',
                      onTap: () {
                        Navigator.pushNamed(context, '/receipt-designer');
                      },
                      showDivider: false,
                    ),
                  ],
                ),
                
                // Aygıt Ayarları
                _buildSettingsCard(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.devices_outlined,
                      title: 'Aygıtlar',
                      subtitle: 'Yazıcılar ve cihazları yönet',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DevicesModule(),
                          ),
                        );
                      },
                      showDivider: false,
                    ),
                  ],
                ),
                
                // Bildirim Ayarları
                _buildSettingsCard(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.notifications_outlined,
                      title: 'Bildirim Ayarları',
                      subtitle: _notificationsEnabled ? 'Açık' : 'Kapalı',
                      trailing: Switch.adaptive(
                        value: _notificationsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _notificationsEnabled = value;
                          });
                          _saveSettings();
                        },
                        activeColor: iconBgColor,
                        inactiveTrackColor: inactiveTrackColor,
                        inactiveThumbColor: inactiveThumbColor,
                      ),
                      onTap: () => Navigator.pushNamed(context, '/notification-settings'),
                    ),
                    _buildSettingsTile(
                      icon: Icons.sms_outlined,
                      title: 'SMS Ayarları',
                      subtitle: _smsNotificationsEnabled ? 'Açık' : 'Kapalı',
                      trailing: Switch.adaptive(
                        value: _smsNotificationsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _smsNotificationsEnabled = value;
                          });
                          _saveSettings();
                        },
                        activeColor: iconBgColor,
                        inactiveTrackColor: inactiveTrackColor,
                        inactiveThumbColor: inactiveThumbColor,
                      ),
                      onTap: () => Navigator.pushNamed(context, '/sms-settings'),
                      showDivider: false,
                    ),
                  ],
                ),
                
                // Görünüm ve Dil Ayarları
                _buildSettingsCard(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.palette_outlined,
                      title: 'Görünüm',
                      subtitle: themeText,
                      trailing: Switch.adaptive(
                        value: themeProvider.isDarkMode,
                        onChanged: (value) {
                          themeProvider.toggleTheme();
                          _saveSettings();
                        },
                        activeColor: iconBgColor,
                        inactiveTrackColor: inactiveTrackColor,
                        inactiveThumbColor: inactiveThumbColor,
                      ),
                      onTap: () {
                        themeProvider.toggleTheme();
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.language_outlined,
                      title: 'Dil ve Para Birimi',
                      subtitle: '$_selectedLanguage - $_selectedCurrency',
                      onTap: () => Navigator.pushNamed(context, '/language-currency-settings'),
                      showDivider: false,
                    ),
                  ],
                ),
                
                // Yedekleme ve Sistem
                _buildSettingsCard(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.backup_outlined,
                      title: 'Yedekleme',
                      subtitle: 'Verileri yedekle ve geri yükle',
                      onTap: () => Navigator.pushNamed(context, '/backup-settings'),
                    ),
                    _buildSettingsTile(
                      icon: Icons.info_outline,
                      title: 'Hakkında',
                      subtitle: 'Uygulama bilgileri',
                      onTap: () => Navigator.pushNamed(context, '/about'),
                      showDivider: false,
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

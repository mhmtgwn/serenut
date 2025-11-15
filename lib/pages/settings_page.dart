import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyAddressController = TextEditingController();
  final _companyTaxController = TextEditingController();
  final _companyEmailController = TextEditingController();

  bool _isLoading = true;
  bool _autoSendSms = true;
  bool _printAfterOrder = false;
  bool _showStockWarning = true;

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
      _autoSendSms = prefs.getBool('auto_send_sms') ?? true;
      _printAfterOrder = prefs.getBool('print_after_order') ?? false;
      _showStockWarning = prefs.getBool('show_stock_warning') ?? true;
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
    await prefs.setBool('auto_send_sms', _autoSendSms);
    await prefs.setBool('print_after_order', _printAfterOrder);
    await prefs.setBool('show_stock_warning', _showStockWarning);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ayarlar kaydedildi'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Şirket Bilgileri
                    _buildSectionTitle(
                        'Şirket Bilgileri', Icons.business_rounded),
                    const SizedBox(height: 16),
                    _buildCompanyInfoCard(),

                    const SizedBox(height: 24),

                    // Genel Ayarlar
                    _buildSectionTitle('Genel Ayarlar', Icons.settings_rounded),
                    const SizedBox(height: 16),
                    _buildGeneralSettingsCard(),

                    const SizedBox(height: 24),

                    // Bildirim Ayarları
                    _buildSectionTitle(
                        'Bildirim Ayarları', Icons.notifications_rounded),
                    const SizedBox(height: 16),
                    _buildNotificationSettingsCard(),

                    const SizedBox(height: 24),

                    // Kaydet Butonu
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text(
                          'Ayarları Kaydet',
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

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF10B981)),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyInfoCard() {
    return Container(
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
              prefixIcon: const Icon(Icons.receipt_long_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
    );
  }

  Widget _buildGeneralSettingsCard() {
    return Container(
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
      child: Column(
        children: [
          SwitchListTile(
            title: const Text(
              'Sipariş Sonrası Otomatik Yazdır',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle:
                const Text('Sipariş oluşturulduğunda otomatik fiş yazdır'),
            value: _printAfterOrder,
            onChanged: (value) => setState(() => _printAfterOrder = value),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.print_rounded, color: Color(0xFF3B82F6)),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text(
              'Stok Uyarıları',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Stok azaldığında uyarı göster'),
            value: _showStockWarning,
            onChanged: (value) => setState(() => _showStockWarning = value),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_rounded, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSettingsCard() {
    return Container(
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
      child: SwitchListTile(
        title: const Text(
          'Otomatik SMS Gönder',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle:
            const Text('Sipariş durumu değiştiğinde müşteriye SMS gönder'),
        value: _autoSendSms,
        onChanged: (value) => setState(() => _autoSendSms = value),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.sms_rounded, color: Color(0xFF10B981)),
        ),
      ),
    );
  }
}

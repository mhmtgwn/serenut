part of '../../settings_page.dart';

extension SettingsPageUiHelpers on _SettingsPageState {
  // �”€�”€ Helper UI Metotları �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  bool _matchesQuery(String f1,
      [String f2 = '',
      String f3 = '',
      String f4 = '',
      String f5 = '',
      String f6 = '',
      String f7 = '',
      String f8 = '']) {
    if (_searchQuery.isEmpty) return true;
    return f1.toLowerCase().contains(_searchQuery) ||
        f2.toLowerCase().contains(_searchQuery) ||
        f3.toLowerCase().contains(_searchQuery) ||
        f4.toLowerCase().contains(_searchQuery) ||
        f5.toLowerCase().contains(_searchQuery) ||
        f6.toLowerCase().contains(_searchQuery) ||
        f7.toLowerCase().contains(_searchQuery) ||
        f8.toLowerCase().contains(_searchQuery);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _kTextSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildRoundedCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildCategoryRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _iOSIconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: _kTextPrimary),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: _kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _iOSIconBadge(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: _kTextPrimary),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _kGreen,
          ),
        ],
      ),
    );
  }

  Widget _iOSIconBadge({required IconData icon, required Color color}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Neutral light grey
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: _kTextSecondary, size: 18),
    );
  }

  // �”€�”€ Database State Güncelleme Metodu �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
  Future<void> _updateSettingField(Settings updated) async {
    try {
      await ref.read(settingsNotifierProvider.notifier).updateSettings(updated);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ayarlar güncellenirken hata oluŸtu: $e'),
          backgroundColor: _kPink,
        ),
      );
    }
  }

  // ”€”€ Yetki / Profil Detay Modalı ”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€”€
  void _showProfileDetails(AuthUser user) {
    final roleLabel = switch (user.role) {
      UserRole.owner => 'Kurucu/Sahip',
      UserRole.admin => 'Yönetici',
      UserRole.sysadmin => 'Sistem Yöneticisi',
      UserRole.manager => 'Müdür',
      UserRole.cashier => 'Kasiyer',
      UserRole.staff => 'Personel',
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FullScreenSettingsPage(
          title: 'Cari Hesap Bilgilerim',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Kullanıcı Adı', user.name),
              _buildInfoRow('Sistem Rolü', roleLabel.toUpperCase()),
              _buildInfoRow('Hesap OluŸturulma Tarihi',
                  user.createdAt.toLocal().toString().substring(0, 16)),
              const SizedBox(height: 16),
              const Text(
                'Sahip OlduŸum Yetkiler',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _kTextPrimary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (user.permissions as List<dynamic>).map((p) {
                  return Chip(
                    label: Text(p.toString(),
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: _kGreen.withOpacity(0.1),
                    side: BorderSide.none,
                    labelStyle: const TextStyle(
                        color: _kGreen, fontWeight: FontWeight.w600),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: _kTextSecondary, fontSize: 14)),
          Text(val,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _kTextPrimary)),
        ],
      ),
    );
  }

  // ── İşletme Bilgileri Düzenleme Ekranı ──
}

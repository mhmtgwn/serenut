import 'package:flutter/material.dart';
import 'profile_settings_page.dart';
import 'devices_page.dart';
import 'message_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMenuCard(
            context,
            icon: Icons.person_rounded,
            title: 'Profil',
            subtitle: 'Şirket bilgileri ve kullanıcı ayarları',
            color: const Color(0xFF10B981),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            icon: Icons.devices_rounded,
            title: 'Aygıtlar',
            subtitle: 'Yazıcı ve donanım yönetimi',
            color: const Color(0xFF3B82F6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DevicesPage()),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            icon: Icons.sms_rounded,
            title: 'Mesaj',
            subtitle: 'SMS ve bildirim ayarları',
            color: const Color(0xFFEF4444),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MessageSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

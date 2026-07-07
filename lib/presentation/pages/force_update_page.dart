// lib/presentation/pages/force_update_page.dart
// Serenut OS — Critical/Mandatory Force Update Screen
// Blueprint: Ecosystem UX & AC 8.3 (Zorunlu Güncelleme)

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ForceUpdatePage extends StatelessWidget {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  const ForceUpdatePage({
    super.key,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  Future<void> _launchUpdateUrl() async {
    if (downloadUrl.isEmpty) return;
    final uri = Uri.tryParse(downloadUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF10B981); // Emerald Green
    const backgroundColor = Color(0xFF0F172A); // Slate 900
    const cardBgColor = Color(0xFF1E293B); // Slate 800
    const textMutedColor = Color(0xFF94A3B8); // Slate 400

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              color: cardBgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: const BorderSide(color: Color(0xFF334155), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Icon(
                        Icons.system_update_alt_rounded,
                        color: Colors.amber,
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'Kritik Güncelleme Gerekli',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Uygulamanın çalışmaya devam edebilmesi için kritik bir güncelleme (v$latestVersion) yüklemeniz gerekmektedir. Lütfen en son sürümü indirin.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: textMutedColor,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Yenilikler & Düzeltmeler:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          releaseNotes,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: downloadUrl.isNotEmpty ? _launchUpdateUrl : null,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        'Şimdi Güncelle',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: backgroundColor,
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

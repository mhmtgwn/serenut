import 'package:flutter/material.dart';

class SmsSettingsPage extends StatefulWidget {
  const SmsSettingsPage({super.key});

  @override
  State<SmsSettingsPage> createState() => _SmsSettingsPageState();
}

class _SmsSettingsPageState extends State<SmsSettingsPage> {
  bool _smsEnabled = false;
  String _smsProvider = 'Turkcell';
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Ayarları'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('SMS Bildirimleri'),
              subtitle: const Text('Müşterilere SMS gönder'),
              value: _smsEnabled,
              onChanged: (value) {
                setState(() {
                  _smsEnabled = value;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'SMS Sağlayıcısı',
                border: OutlineInputBorder(),
              ),
              value: _smsProvider,
              items: const [
                DropdownMenuItem(value: 'Turkcell', child: Text('Turkcell')),
                DropdownMenuItem(value: 'Vodafone', child: Text('Vodafone')),
                DropdownMenuItem(value: 'Türk Telekom', child: Text('Türk Telekom')),
              ],
              onChanged: (value) {
                setState(() {
                  _smsProvider = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Anahtarı',
                border: OutlineInputBorder(),
                helperText: 'SMS sağlayıcısından alınan API anahtarı',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SMS ayarları kaydedildi')),
                );
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class LanguageCurrencySettingsPage extends StatefulWidget {
  const LanguageCurrencySettingsPage({super.key});

  @override
  State<LanguageCurrencySettingsPage> createState() => _LanguageCurrencySettingsPageState();
}

class _LanguageCurrencySettingsPageState extends State<LanguageCurrencySettingsPage> {
  String _selectedLanguage = 'Türkçe';
  String _selectedCurrency = '₺';

  final List<Map<String, String>> _languages = [
    {'code': 'tr', 'name': 'Türkçe'},
    {'code': 'en', 'name': 'English'},
    {'code': 'de', 'name': 'Deutsch'},
    {'code': 'fr', 'name': 'Français'},
  ];

  final List<Map<String, String>> _currencies = [
    {'code': 'TRY', 'symbol': '₺', 'name': 'Türk Lirası'},
    {'code': 'USD', 'symbol': '\$', 'name': 'US Dollar'},
    {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
    {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dil ve Para Birimi'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dil Seçimi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _languages.map((language) {
                  return RadioListTile<String>(
                    title: Text(language['name']!),
                    value: language['name']!,
                    groupValue: _selectedLanguage,
                    onChanged: (value) {
                      setState(() {
                        _selectedLanguage = value!;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Para Birimi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _currencies.map((currency) {
                  return RadioListTile<String>(
                    title: Text('${currency['symbol']} - ${currency['name']}'),
                    value: currency['symbol']!,
                    groupValue: _selectedCurrency,
                    onChanged: (value) {
                      setState(() {
                        _selectedCurrency = value!;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Dil: $_selectedLanguage, Para Birimi: $_selectedCurrency olarak kaydedildi'),
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

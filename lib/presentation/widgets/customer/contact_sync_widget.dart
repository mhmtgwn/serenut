import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/customer_service.dart';

class ContactSyncWidget extends StatefulWidget {
  final VoidCallback onSyncCompleted;

  const ContactSyncWidget({
    Key? key,
    required this.onSyncCompleted,
  }) : super(key: key);

  @override
  State<ContactSyncWidget> createState() => _ContactSyncWidgetState();
}

class _ContactSyncWidgetState extends State<ContactSyncWidget> {
  static const String _firstSyncKey = 'first_sync_completed';
  bool _isSyncing = false;
  int _syncProgress = 0;

  Future<void> syncContacts() async {
    if (!mounted) return;

    setState(() {
      _isSyncing = true;
      _syncProgress = 0;
    });

    try {
      // İzin kontrolü
      var contactPermission = await Permission.contacts.request();
      if (contactPermission.isGranted) {
        // İlerleme göstergesini başlat
        if (mounted) {
          setState(() {
            _syncProgress = 5;
          });
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // Rehberi oku
        if (mounted) {
          setState(() {
            _syncProgress = 10;
          });
        }

        final contacts =
            await FlutterContacts.getContacts(withProperties: true);

        // İlerleme göstergesini güncelle
        if (mounted) {
          setState(() {
            _syncProgress = 30;
          });
        }

        if (mounted) {
          setState(() {
            _syncProgress = 40;
          });
        }

        // Kişileri veritabanına ekle
        int processedCount = 0;
        for (var contact in contacts) {
          if (!mounted) break;

          try {
            // Kişi bilgilerini müşteri olarak ekle
            final customerData = {
              'name': contact.displayName,
              'displayName': contact.displayName,
              'phone':
                  contact.phones.isNotEmpty ? contact.phones.first.number : '',
              'email':
                  contact.emails.isNotEmpty ? contact.emails.first.address : '',
            };

            await CustomerService.instance.addCustomer(customerData);
            processedCount++;
          } catch (e) {
            // Hata durumunda devam et
            debugPrint('Kişi eklenirken hata: $e');
          }

          // İlerleme güncelle
          int progress = 40 + ((processedCount / contacts.length) * 50).round();
          if (mounted) {
            setState(() {
              _syncProgress = progress;
            });
          }
        }

        if (mounted) {
          setState(() {
            _syncProgress = 100;
          });
        }

        // Başarı bildirimi
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${contacts.length} kişi başarıyla senkronize edildi'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // İlk senkronizasyon tamamlandı işareti
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_firstSyncKey, true);

        // Callback çağır
        widget.onSyncCompleted();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rehber erişim izni gerekli'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Senkronizasyon hatası: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.sync, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Rehber Senkronizasyonu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isSyncing) ...[
              LinearProgressIndicator(
                value: _syncProgress / 100,
              ),
              const SizedBox(height: 8),
              Text('Senkronize ediliyor... %$_syncProgress'),
            ] else ...[
              const Text(
                'Telefon rehberinizden kişileri içe aktarabilirsiniz.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: syncContacts,
                icon: const Icon(Icons.sync),
                label: const Text('Rehberi Senkronize Et'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

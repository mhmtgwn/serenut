import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path/path.dart' as path_lib;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../services/customer_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../utils/notification_service.dart';
import '../widgets/add_customer_form.dart';

class CustomersContent extends StatefulWidget {
  final bool isSelectionMode;

  const CustomersContent({super.key, this.isSelectionMode = false});

  @override
  State<CustomersContent> createState() => CustomersContentState();
}

class CustomersContentState extends State<CustomersContent> {
  //static const String _permissionRequestedKey = 'contact_permission_requested';
  static const String _firstSyncKey = 'first_sync_completed';
  List<Map<String, dynamic>> _customers = [];
  String _searchQuery = '';
  bool _isSyncing = false;
  int _syncProgress = 0;
  final List<Contact> _contacts = [];
  final TextEditingController _searchController = TextEditingController();
  
  // Public erişim için getter
  TextEditingController get searchController => _searchController;
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Sadece mevcut müşterileri yükle
    await _loadCustomers();
    
    // İzin kontrolünü burada yapmıyoruz, butona tıklandığında kontrol edilecek
  }

  Future<void> _checkAndRequestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPermission = await FlutterContacts.requestPermission();
    
    if (hasPermission) {
      await _loadContacts();
      await prefs.setBool(_firstSyncKey, true);
    }
  }

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
          // Kullanıcının ilerleme göstergesini görebilmesi için kısa bir bekleme
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // Rehberi oku
        if (mounted) {
          setState(() {
            _syncProgress = 10;
          });
        }
        
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        
        // İlerleme göstergesini güncelle
        if (mounted) {
          setState(() {
            _syncProgress = 30;
          });
          // Kullanıcının ilerleme göstergesini görebilmesi için kısa bir bekleme
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // Rehberi işle
        final List<Contact> filteredContacts = [];
        for (var contact in contacts) {
          if (contact.displayName.isNotEmpty) {
            filteredContacts.add(contact);
          }
        }
        
        // İlerleme göstergesini güncelle
        if (mounted) {
          setState(() {
            _syncProgress = 50;
          });
          // Kullanıcının ilerleme göstergesini görebilmesi için kısa bir bekleme
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // Veritabanına ekle
        final databaseService = DatabaseService.instance;
        int addedCount = 0;
        int updatedCount = 0;
        int totalContacts = filteredContacts.length;
        
        for (int i = 0; i < totalContacts; i++) {
          final contact = filteredContacts[i];
          
          // İlerleme göstergesini güncelle (50'den 90'a kadar)
          if (mounted && i % 5 == 0) { // Her 5 kişide bir güncelle
            final progress = 50 + ((i / totalContacts) * 40).round();
            setState(() {
              _syncProgress = progress;
            });
          }
          
          // Telefon numarası kontrolü
          if (contact.phones.isNotEmpty) {
            final phone = contact.phones.first.number.replaceAll(RegExp(r'[^\d+]'), '');
            
            // Veritabanında bu telefon numarasına sahip müşteri var mı kontrol et
            final existingCustomers = await databaseService.getCustomerByPhone(phone);
            
            if (existingCustomers.isEmpty) {
              // Yeni müşteri ekle
              await databaseService.addCustomer({
                'displayName': contact.displayName,
                'firstName': contact.name.first,
                'lastName': contact.name.last,
                'phone': phone,
                'email': contact.emails.isNotEmpty ? contact.emails.first.address : '',
                'company': contact.organizations.isNotEmpty ? contact.organizations.first.company : '',
                'jobTitle': contact.organizations.isNotEmpty ? contact.organizations.first.title : '',
                'notes': 'Rehberden senkronize edildi',
                'syncId': contact.id,
              });
              addedCount++;
            } 
            else {
              // Mevcut müşteriyi güncelle
              final existingCustomer = existingCustomers.first;
              await databaseService.updateCustomer({
                'id': existingCustomer['id'],
                'displayName': contact.displayName,
                'firstName': contact.name.first,
                'lastName': contact.name.last,
                'phone': phone,
                'email': contact.emails.isNotEmpty ? contact.emails.first.address : '',
                'company': contact.organizations.isNotEmpty ? contact.organizations.first.company : '',
                'jobTitle': contact.organizations.isNotEmpty ? contact.organizations.first.title : '',
                'notes': existingCustomer['notes'] ?? 'Rehberden senkronize edildi',
                'syncId': contact.id,
              });
              updatedCount++;
            }
          }
        }
        
        // İlerleme göstergesini güncelle
        if (mounted) {
          setState(() {
            _syncProgress = 90;
          });
          // Kullanıcının ilerleme göstergesini görebilmesi için kısa bir bekleme
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // Müşteri listesini yenile
        await _loadCustomers();
        
        // İlerleme göstergesini tamamla
        if (mounted) {
          setState(() {
            _contacts.clear();
            _contacts.addAll(contacts);
            _contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
            _syncProgress = 100;
          });
          
          // Kısa bir süre sonra ilerleme göstergesini kapat
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _isSyncing = false;
                _syncProgress = 0;
              });
            }
          });
          
          // Başarılı bildirim göster
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$addedCount yeni kişi eklendi, $updatedCount kişi güncellendi'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _isSyncing = false;
            _syncProgress = 0;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rehbere erişim izni verilmedi'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Rehber senkronizasyon hatası: $e');
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = 0;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rehber senkronize edilirken bir hata oluştu: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadContacts() async {
    var contactPermission = await Permission.contacts.request();
    if (contactPermission.isGranted) {
      setState(() {
        _isSyncing = true;
        _syncProgress = 0;
      });

      try {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        
        // Rehberden alınan kişileri veritabanına kaydet
        int addedCount = 0;
        int updatedCount = 0;
        
        for (var contact in contacts) {
          if (contact.phones.isNotEmpty) {
            final phone = contact.phones.first.number.replaceAll(RegExp(r'[^\d+]'), '');
            
            // Veritabanında bu telefon numarasına sahip müşteri var mı kontrol et
            final existingCustomers = await DatabaseService.instance.getCustomerByPhone(phone);
            
            if (existingCustomers.isEmpty) {
              // Yeni müşteri ekle
              await DatabaseService.instance.addCustomer({
                'displayName': contact.displayName,
                'firstName': contact.name.first,
                'lastName': contact.name.last,
                'phone': phone,
                'email': contact.emails.isNotEmpty ? contact.emails.first.address : '',
                'company': contact.organizations.isNotEmpty ? contact.organizations.first.company : '',
                'jobTitle': contact.organizations.isNotEmpty ? contact.organizations.first.title : '',
                'notes': 'Rehberden senkronize edildi',
                'syncId': contact.id,
              });
              addedCount++;
            }
            else {
              // Mevcut müşteriyi güncelle
              final existingCustomer = existingCustomers.first;
              await DatabaseService.instance.updateCustomer({
                'id': existingCustomer['id'],
                'displayName': contact.displayName,
                'firstName': contact.name.first,
                'lastName': contact.name.last,
                'phone': phone,
                'email': contact.emails.isNotEmpty ? contact.emails.first.address : '',
                'company': contact.organizations.isNotEmpty ? contact.organizations.first.company : '',
                'jobTitle': contact.organizations.isNotEmpty ? contact.organizations.first.title : '',
                'notes': existingCustomer['notes'] ?? 'Rehberden senkronize edildi',
                'syncId': contact.id,
              });
              updatedCount++;
            }
          }
        }
        
        // Müşteri listesini güncelle
        await _loadCustomers();
        
        setState(() {
          _contacts.clear();
          _contacts.addAll(contacts);
          _contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
          _isSyncing = false;
          _syncProgress = 100;
        });
        
        if (mounted) {
          // Başarılı bildirim göster
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$addedCount yeni kişi eklendi, $updatedCount kişi güncellendi'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isSyncing = false;
          _syncProgress = 0;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kişiler yüklenirken hata oluştu: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      await FlutterContacts.requestPermission();
    }
  }

  Future<void> _loadCustomers() async {
    final customers = await DatabaseService.instance.getAllCustomers();
    if (mounted) {
      setState(() {
        _customers = customers;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    return _customers.where((customer) {
      final name = customer['displayName'].toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _showAddCustomerDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => AddCustomerForm(
          onCustomerAdded: () {
            _loadCustomers();
          },
        ),
      ),
    );
  }

  // Public erişim için metotlar
  void filterCustomers(String query) {
    _filterCustomers(query);
  }

  void showAddCustomerDialog() {
    _showAddCustomerDialog();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkBackgroundColor : AppTheme.lightBackgroundColor;
    final cardColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final secondaryTextColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final dividerColor = isDarkMode ? Colors.white24 : Colors.black12;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: widget.isSelectionMode 
        ? AppBar(
            title: const Text('Müşteri Seç'),
            backgroundColor: isDarkMode ? AppTheme.darkSurfaceColor : AppTheme.lightSurfaceColor,
            foregroundColor: isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor,
            elevation: 2,
            shadowColor: isDarkMode ? AppTheme.darkShadowColor : AppTheme.lightShadowColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          )
        : null,
      body: Stack(
        children: [
          // Senkronizasyon ilerleme göstergesi
          if (_isSyncing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              margin: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0, bottom: 8.0),
              decoration: BoxDecoration(
                color: isDarkMode ? AppTheme.primaryColor.withAlpha(51) : AppTheme.primaryColor.withAlpha(26),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sync, size: 16, color: isDarkMode ? Colors.white70 : AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Kişiler senkronize ediliyor...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$_syncProgress%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _syncProgress / 100,
                    backgroundColor: isDarkMode ? Colors.white24 : Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkMode ? AppTheme.primaryColor : AppTheme.primaryColor,
                    ),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            ),
          
          Column(
            children: [
              // Müşteri listesi
              Expanded(
                child: _filteredCustomers.isEmpty
                    ? Center(
                        child: Text(
                          'Müşteri bulunamadı',
                          style: TextStyle(color: textColor),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCustomers,
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16), // Alt kısımda boşluk
                          itemCount: _filteredCustomers.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: dividerColor,
                          ),
                          itemBuilder: (context, index) {
                            final customer = _filteredCustomers[index];
                            return _buildCustomerCard(customer, cardColor, textColor, secondaryTextColor);
                          },
                        ),
                      ),
              ),
            ],
          ),
          
          // Alt kısımdaki arama kutusu ve butonlar - NavBar'a taşındığı için kaldırıyoruz
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer, Color cardColor, Color textColor, Color secondaryTextColor) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: widget.isSelectionMode
            ? () => Navigator.pop(context, customer)
            : () => _showCustomerDetails(customer),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                child: Text(
                  customer['displayName'] != null && customer['displayName'].toString().isNotEmpty
                      ? customer['displayName'][0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer['displayName'] ?? 'İsimsiz Müşteri',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    if (customer['phone'] != null && customer['phone'].toString().isNotEmpty)
                      Text(
                        customer['phone'],
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryTextColor,
                        ),
                      ),
                  ],
                ),
              ),
              widget.isSelectionMode
                  ? Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.primaryColor,
                    )
                  : Icon(
                      Icons.chevron_right,
                      color: secondaryTextColor,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _filterCustomers(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _showCustomerDetails(Map<String, dynamic> customer) {
    if (widget.isSelectionMode) {
      // Seçim modunda ise, müşteriyi seç ve geri dön
      Navigator.pop(context, customer);
    } else {
      // Normal modda ise, müşteri detaylarını göster
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final isDarkMode = themeProvider.isDarkMode;
      final textColor = isDarkMode ? Colors.white : Colors.black87;
      final secondaryTextColor = isDarkMode ? Colors.white70 : Colors.black54;
      final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
      final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
      
      // Müşteri ID'sini al
      final customerId = customer['id'] as int;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (BuildContext context, setState) {
              return DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                expand: false,
                builder: (BuildContext context, scrollController) {
                  return FutureBuilder<double>(
                    future: CustomerService.instance.getCustomerTotalDebt(customerId),
                    builder: (BuildContext context, snapshot) {
                      final totalDebt = snapshot.data ?? 0.0;
                      
                      return Column(
                        children: [
                          // Başlık çubuğu
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.black : Colors.white,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              border: Border(
                                bottom: BorderSide(
                                  color: borderColor,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Müşteri Detayları',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close, color: textColor),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                          
                          // Müşteri bilgileri
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              children: [
                                // Müşteri kartı
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: backgroundColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: AppTheme.primaryColor,
                                            radius: 24,
                                            child: Text(
                                              customer['displayName'] != null && customer['displayName'].toString().isNotEmpty
                                                  ? customer['displayName'][0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  customer['displayName'] ?? 'İsimsiz Müşteri',
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: textColor,
                                                  ),
                                                ),
                                                if (customer['phone'] != null && customer['phone'].toString().isNotEmpty)
                                                  Text(
                                                    customer['phone'],
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: secondaryTextColor,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Divider(color: borderColor),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Toplam Borç:',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                          Text(
                                            '${totalDebt.toStringAsFixed(2)} ₺',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: totalDebt > 0 ? Colors.red : Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                
                                const SizedBox(height: 24),
                                
                                // Ödeme alma butonu (borç varsa)
                                if (totalDebt > 0)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context); // Mevcut diyaloğu kapat
                                        _showCollectPaymentDialog(customer, totalDebt);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text(
                                        'Ödeme Al',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                
                                const SizedBox(height: 24),
                                
                                // Sipariş geçmişi başlığı
                                Text(
                                  'Sipariş Geçmişi',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                
                                const SizedBox(height: 8),
                                
                                // Sipariş geçmişi
                                FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _getCustomerOrders(customerId),
                                  builder: (BuildContext context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }
                                    
                                    if (snapshot.hasError) {
                                      return const Center(
                                        child: Text(
                                          'Sipariş geçmişi yüklenirken hata oluştu',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      );
                                    }
                                    
                                    final orders = snapshot.data ?? [];
                                    
                                    if (orders.isEmpty) {
                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: backgroundColor,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: borderColor,
                                            width: 1,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Henüz sipariş bulunmuyor',
                                            style: TextStyle(color: secondaryTextColor),
                                          ),
                                        ),
                                      );
                                    }
                                    
                                    return ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: orders.length,
                                      itemBuilder: (context, index) {
                                        final order = orders[index];
                                        final orderDate = DateTime.parse(order['orderDate']);
                                        final formattedDate = '${orderDate.day}/${orderDate.month}/${orderDate.year}';
                                        final totalAmount = order['totalAmount'] as double? ?? 0.0;
                                        final paidAmount = order['paidAmount'] as double? ?? 0.0;
                                        final remainingAmount = totalAmount - paidAmount;
                                        
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: backgroundColor,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: borderColor,
                                              width: 1,
                                            ),
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.all(12),
                                            title: Text(
                                              'Sipariş #${order['id']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: textColor,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Tarih: $formattedDate',
                                                  style: TextStyle(color: secondaryTextColor),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Durum: ${order['orderStatus']}',
                                                  style: TextStyle(color: secondaryTextColor),
                                                ),
                                              ],
                                            ),
                                            trailing: Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '${totalAmount.toStringAsFixed(2)} ₺',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: textColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  remainingAmount > 0 
                                                      ? 'Kalan: ${remainingAmount.toStringAsFixed(2)} ₺' 
                                                      : 'Ödendi',
                                                  style: TextStyle(
                                                    color: remainingAmount > 0 ? Colors.red : Colors.green,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    }
  }
  
  // Müşterinin siparişlerini getir
  Future<List<Map<String, dynamic>>> _getCustomerOrders(int customerId) async {
    try {
      final dbPath = await getDatabasesPath();
      final dbFilePath = path_lib.join(dbPath, 'orders.db');
      
      // Sipariş veritabanını aç
      final orderDb = await openDatabase(dbFilePath, readOnly: true);
      
      // Müşterinin tüm siparişlerini al
      final List<Map<String, dynamic>> orders = await orderDb.query(
        'orders',
        where: 'customerId = ?',
        whereArgs: [customerId],
        orderBy: 'orderDate DESC',
      );
      
      await orderDb.close();
      return orders;
    } catch (e) {
      debugPrint('Müşteri siparişleri alınırken hata: ${e.toString()}');
      return [];
    }
  }
  
  // Ödeme alma diyaloğunu göster
  void _showCollectPaymentDialog(Map<String, dynamic> customer, double totalDebt) {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController notesController = TextEditingController();
    String paymentMethod = 'Nakit';
    
    amountController.text = totalDebt.toString();
    
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = themeProvider.isDarkMode;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final backgroundColor = isDarkMode ? AppTheme.darkBackgroundColor : AppTheme.lightBackgroundColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;
    
    // Ödeme işlemini gerçekleştiren fonksiyon
    void processPayment(BuildContext dialogContext) async {
      final amount = double.tryParse(amountController.text);
      
      if (amount != null && amount > 0) {
        try {
          // Müşterinin borçlarından düş
          final bool success = await CustomerService.instance.reduceCustomerDebt(
            customer['id'] as int, 
            amount
          );
          
          // Widget hala ağaçta mı kontrol et
          if (!mounted) return;
          
          // Dialog'u kapat
          // ignore: use_build_context_synchronously
          Navigator.pop(dialogContext);
          
          // Sonucu göster
          if (success) {
            // Başarılı mesajı göster
            _showSuccessMessage('Ödeme başarıyla kaydedildi');
            
            // Müşteri listesini yenile
            _loadCustomers();
          } else {
            // Hata mesajı göster
            _showErrorMessage('Ödeme kaydedilirken bir hata oluştu');
          }
        } catch (e) {
          // Widget hala ağaçta mı kontrol et
          if (!mounted) return;
          
          // Dialog'u kapat
          // ignore: use_build_context_synchronously
          Navigator.pop(dialogContext);
          
          // Hata mesajı göster
          _showErrorMessage('Hata: ${e.toString()}');
        }
      } else {
        // Bu kısım asenkron değil, doğrudan context kullanılabilir
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text('Lütfen geçerli bir ödeme tutarı girin'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Text(
          'Ödeme Al',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Müşteri: ${customer['displayName']}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Text(
                'Toplam Borç: ${totalDebt.toStringAsFixed(2)} ₺',
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText: 'Ödeme Tutarı',
                  hintText: 'Örn: 100.50',
                  suffixText: '₺',
                  labelStyle: TextStyle(color: textColor.withAlpha(179)),
                  hintStyle: TextStyle(color: textColor.withAlpha(127)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primaryColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Örn: Borç ödemesi',
                  labelStyle: TextStyle(color: textColor.withAlpha(179)),
                  hintStyle: TextStyle(color: textColor.withAlpha(127)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primaryColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: TextStyle(color: textColor),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: InputDecoration(
                  labelText: 'Ödeme Yöntemi',
                  labelStyle: TextStyle(color: textColor.withAlpha(179)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primaryColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                dropdownColor: backgroundColor,
                style: TextStyle(color: textColor),
                items: [
                  DropdownMenuItem(
                    value: 'Nakit', 
                    child: Text(
                      'Nakit',
                      style: TextStyle(color: textColor),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Banka', 
                    child: Text(
                      'Banka',
                      style: TextStyle(color: textColor),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Kredi Kartı', 
                    child: Text(
                      'Kredi Kartı',
                      style: TextStyle(color: textColor),
                    ),
                  ),
                ],
                onChanged: (value) {
                  paymentMethod = value!;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
            ),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => processPayment(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ödeme Al'),
          ),
        ],
      ),
    );
  }
  
  // Başarı mesajı göster
  void _showSuccessMessage(String message) {
    if (!mounted) return;
    
    // BuildContext'i güvenli bir şekilde kullan
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  // Hata mesajı göster
  void _showErrorMessage(String message) {
    if (!mounted) return;
    
    // BuildContext'i güvenli bir şekilde kullan
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // İzin dialog'u
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Rehber İzni Gerekli'),
        content: const Text('Müşteri listenizi rehberinizden otomatik olarak yüklemek için rehber erişim iznine ihtiyacımız var.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final status = await Permission.contacts.request();
              if (status.isGranted && mounted) {
                syncContacts();
              }
            },
            child: const Text('İzin Ver'),
          ),
        ],
      ),
    );
  }
  
  // Ayarlar dialog'u
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('İzinler Kapalı'),
        content: const Text('Rehber erişim izni devre dışı bırakıldı. Rehber senkronizasyonu için telefonunuzun ayarlarından uygulama izinlerini açmanız gerekiyor.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Ayarlara Git'),
          ),
        ],
      ),
    );
  }
} 

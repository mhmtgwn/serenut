import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';

class ReceiptPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> receiptData;

  const ReceiptPreviewDialog({
    Key? key,
    required this.receiptData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode ? AppTheme.darkCardColor : AppTheme.lightCardColor;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : AppTheme.lightPrimaryTextColor;
    final secondaryTextColor = isDarkMode ? AppTheme.darkSecondaryTextColor : AppTheme.lightSecondaryTextColor;
    final borderColor = isDarkMode ? AppTheme.darkBorderColor : AppTheme.lightBorderColor;

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Fiş Önizleme',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Fiş içeriği
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildReceiptContent(textColor, secondaryTextColor),
              ),
            ),
            
            // Butonlar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: borderColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Kapat'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(true); // Yazdırma onayı
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Yazdır'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptContent(Color textColor, Color secondaryTextColor) {
    final items = receiptData['items'] as List<Map<String, dynamic>>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // İşletme bilgileri
        _buildCenteredText(receiptData['businessName'] ?? 'İŞLETME', textColor, 18, true),
        if (receiptData['address']?.isNotEmpty == true)
          _buildCenteredText(receiptData['address'], secondaryTextColor, 14),
        if (receiptData['phone']?.isNotEmpty == true)
          _buildCenteredText(receiptData['phone'], secondaryTextColor, 14),
        if (receiptData['taxInfo']?.isNotEmpty == true)
          _buildCenteredText(receiptData['taxInfo'], secondaryTextColor, 14),
        
        const SizedBox(height: 16),
        _buildDivider(),
        
        // Fiş numarası ve tarih
        _buildCenteredText(receiptData['receiptNumber'] ?? '', textColor, 16, true),
        _buildCenteredText(receiptData['date'] ?? '', secondaryTextColor, 14),
        
        const SizedBox(height: 16),
        _buildDivider(),
        
        // Müşteri bilgileri
        if (receiptData['customerName']?.isNotEmpty == true) ...[
          _buildLeftText('Müşteri:', textColor, 14, true),
          _buildLeftText(receiptData['customerName'], secondaryTextColor, 14),
          if (receiptData['customerPhone']?.isNotEmpty == true)
            _buildLeftText(receiptData['customerPhone'], secondaryTextColor, 14),
          if (receiptData['customerAddress']?.isNotEmpty == true)
            _buildLeftText(receiptData['customerAddress'], secondaryTextColor, 14),
          const SizedBox(height: 12),
        ],
        
        _buildDivider(),
        
        // Ürünler
        _buildLeftText('Ürünler:', textColor, 14, true),
        const SizedBox(height: 8),
        
        ...items.map((item) => _buildProductRow(item, textColor, secondaryTextColor)),
        
        const SizedBox(height: 12),
        _buildDivider(),
        
        // Toplam bilgileri
        _buildTotalRow('Ara Toplam:', receiptData['subtotal'], textColor, secondaryTextColor),
        if ((receiptData['tax'] as double) > 0)
          _buildTotalRow('KDV:', receiptData['tax'], textColor, secondaryTextColor),
        _buildTotalRow('TOPLAM:', receiptData['total'], textColor, secondaryTextColor, true),
        
        if ((receiptData['paidAmount'] as double) > 0) ...[
          _buildTotalRow('Ödenen:', receiptData['paidAmount'], textColor, secondaryTextColor),
          if ((receiptData['remainingAmount'] as double) > 0)
            _buildTotalRow('Kalan:', receiptData['remainingAmount'], textColor, secondaryTextColor),
        ],
        
        const SizedBox(height: 12),
        _buildDivider(),
        
        // Ödeme yöntemi
        if (receiptData['paymentMethod']?.isNotEmpty == true)
          _buildLeftText('Ödeme: ${receiptData['paymentMethod']}', textColor, 14),
        
        // Notlar
        if (receiptData['notes']?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _buildLeftText('Not: ${receiptData['notes']}', secondaryTextColor, 12),
        ],
        
        const SizedBox(height: 16),
        _buildDivider(),
        
        // Alt bilgi
        _buildCenteredText(receiptData['footerNote'] ?? 'Teşekkür ederiz!', secondaryTextColor, 12),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCenteredText(String text, Color color, double fontSize, [bool isBold = false]) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildLeftText(String text, Color color, double fontSize, [bool isBold = false]) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: Colors.grey.withAlpha(77),
      margin: const EdgeInsets.symmetric(vertical: 8),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> item, Color textColor, Color secondaryTextColor) {
    final currencyFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              item['name'] ?? '',
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${item['quantity']}x',
              style: TextStyle(color: secondaryTextColor, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              currencyFormat.format(item['subtotal'] ?? 0),
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, dynamic value, Color textColor, Color secondaryTextColor, [bool isTotal = false]) {
    final currencyFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? textColor : secondaryTextColor,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            currencyFormat.format(value ?? 0),
            style: TextStyle(
              color: isTotal ? textColor : secondaryTextColor,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

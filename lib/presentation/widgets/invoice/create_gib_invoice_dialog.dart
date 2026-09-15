// lib/presentation/widgets/invoice/create_gib_invoice_dialog.dart
// Serenut OS — Ücretsiz GİB e-Arşiv Fatura Kesme ve SMS Onay Penceresi

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/pages/settings/widgets/gib_settings_dialog.dart';
import 'package:serenutos/providers/gib_invoice_providers.dart';

class CreateGibInvoiceDialog extends ConsumerStatefulWidget {
  final SaleEntity? sale;
  final CustomerEntity? customer;
  final List<GibInvoiceItem>? items;
  final double totalAmount;

  const CreateGibInvoiceDialog({
    super.key,
    this.sale,
    this.customer,
    this.items,
    required this.totalAmount,
  });

  static Future<void> show(
    BuildContext context, {
    SaleEntity? sale,
    CustomerEntity? customer,
    List<GibInvoiceItem>? items,
    required double totalAmount,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateGibInvoiceDialog(
        sale: sale,
        customer: customer,
        items: items,
        totalAmount: totalAmount,
      ),
    );
  }

  @override
  ConsumerState<CreateGibInvoiceDialog> createState() =>
      _CreateGibInvoiceDialogState();
}

class _CreateGibInvoiceDialogState
    extends ConsumerState<CreateGibInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();

  // Alıcı Formu
  final _identifierCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _taxOfficeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  GibRecipientType _recipientType = GibRecipientType.consumer;
  List<GibInvoiceItem> _invoiceItems = [];

  // İşlem Adımları: 0 = Form, 1 = SMS Bekleniyor, 2 = Başarılı / İmzalandı
  int _step = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // SMS Adımı
  final _smsCodeCtrl = TextEditingController();
  String? _maskedPhone;
  GibInvoiceRecord? _currentRecord;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    final creds = ref.read(gibCredentialsProvider);
    final vatRate = creds.defaultVatRate;

    // Ürünleri hazırla
    if (widget.items != null && widget.items!.isNotEmpty) {
      _invoiceItems = List.from(widget.items!);
    } else if (widget.sale != null) {
      _invoiceItems = widget.sale!.items.map((item) {
        final grossPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        // KDV hariç fiyat hesapla (varsayılan KDV oranı ile)
        final netPrice = grossPrice / (1.0 + (vatRate / 100.0));
        return GibInvoiceItem(
          name: (item['product_name'] as String?) ?? 'Ürün',
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
          unitPrice: netPrice,
          vatRate: vatRate,
        );
      }).toList();
    } else {
      _invoiceItems = [
        GibInvoiceItem(
          name: 'Perakende Satış',
          quantity: 1.0,
          unitPrice: widget.totalAmount / (1.0 + (vatRate / 100.0)),
          vatRate: vatRate,
        ),
      ];
    }

    // Müşteri bilgisi varsa doldur
    if (widget.customer != null) {
      _nameCtrl.text = widget.customer!.name;
      _phoneCtrl.text = widget.customer!.phone;
      _emailCtrl.text = widget.customer!.email;
      _recipientType = GibRecipientType.individual;
      _identifierCtrl.text = '';
      _cityCtrl.text = 'Türkiye';
    } else {
      _fillConsumerDefaults();
    }
  }

  void _fillConsumerDefaults() {
    setState(() {
      _recipientType = GibRecipientType.consumer;
      _identifierCtrl.text = '11111111111';
      _nameCtrl.text = 'Nihai Tüketici';
      _cityCtrl.text = 'Türkiye';
      _taxOfficeCtrl.text = '';
      _addressCtrl.text = '';
      _districtCtrl.text = '';
    });
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _nameCtrl.dispose();
    _taxOfficeCtrl.dispose();
    _addressCtrl.dispose();
    _districtCtrl.dispose();
    _cityCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _noteCtrl.dispose();
    _smsCodeCtrl.dispose();
    super.dispose();
  }

  double get _totalWithoutVat =>
      _invoiceItems.fold(0.0, (sum, item) => sum + item.lineTotalWithoutVat);
  double get _totalVat =>
      _invoiceItems.fold(0.0, (sum, item) => sum + item.vatAmount);
  double get _totalAmount => _totalWithoutVat + _totalVat;

  /// 1. Adım: GİB Portal'e Gönder ve SMS Şifresi İste
  Future<void> _submitDraft() async {
    final creds = ref.read(gibCredentialsProvider);
    if (!creds.isConfigured) {
      _showNotConfiguredDialog();
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(gibInvoiceServiceProvider);
      final recipient = GibInvoiceRecipient(
        identifier: _identifierCtrl.text.trim(),
        titleOrName: _nameCtrl.text.trim(),
        taxOffice: _taxOfficeCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        district: _districtCtrl.text.trim(),
        city: _cityCtrl.text.trim().isNotEmpty ? _cityCtrl.text.trim() : 'Türkiye',
        phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
        type: _recipientType,
      );

      // Taslağı GİB'e gönder
      final record = await service.createAndSubmitDraft(
        username: creds.username,
        password: creds.password,
        recipient: recipient,
        items: _invoiceItems,
        totalWithoutVat: _totalWithoutVat,
        totalVat: _totalVat,
        totalAmount: _totalAmount,
        saleId: widget.sale?.id,
        customerId: widget.customer?.id,
        note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
      );

      // GİB SMS Şifresi İste
      final phone = await service.requestSmsCode(
        username: creds.username,
        password: creds.password,
      );

      if (mounted) {
        setState(() {
          _currentRecord = record;
          _maskedPhone = phone;
          _step = 1; // SMS onay adımı
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '');
        });
      }
    }
  }

  /// 2. Adım: SMS Şifresini Doğrula ve İmzala
  Future<void> _verifySmsAndSign() async {
    final code = _smsCodeCtrl.text.trim();
    if (code.length < 5) {
      setState(() => _errorMessage = 'Lütfen geçerli bir SMS onay kodu giriniz.');
      return;
    }

    final creds = ref.read(gibCredentialsProvider);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(gibInvoiceServiceProvider);
      final signedRecord = await service.verifySmsAndSign(
        username: creds.username,
        password: creds.password,
        invoiceId: _currentRecord!.id,
        gibUuid: _currentRecord!.gibUuid!,
        smsCode: code,
      );

      if (mounted) {
        setState(() {
          _currentRecord = signedRecord;
          _step = 2; // Başarı adımı
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'İmzalama Başarısız: ${e.toString().replaceAll('Exception:', '')}';
        });
      }
    }
  }

  void _showNotConfiguredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GİB Ayarları Eksik'),
        content: const Text(
          'e-Arşiv fatura kesebilmek için önce Ayarlar bölümünden GİB İnteraktif Vergi Dairesi kullanıcı adı ve şifrenizi tanımlamalısınız.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              GibSettingsDialog.show(context);
            },
            child: const Text('Ayarları Aç'),
          ),
        ],
      ),
    );
  }

  void _shareViaWhatsApp() {
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final name = _nameCtrl.text;
    final total = _totalAmount.toStringAsFixed(2);
    final uuid = _currentRecord?.gibUuid ?? '';

    final message = '''Sayın $name,
$total ₺ tutarındaki e-Arşiv Faturanız Gelir İdaresi Başkanlığı (GİB) sisteminde onaylanarak düzenlenmiştir.
Fatura Takip / ETTN No: $uuid
Bizi tercih ettiğiniz için teşekkür ederiz.''';

    final uri = Uri.parse(
        'https://wa.me/${phone.startsWith('90') ? phone : '90$phone'}?text=${Uri.encodeComponent(message)}');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: _step == 0
                      ? _buildFormStep()
                      : (_step == 1 ? _buildSmsStep() : _buildSuccessStep()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: POSColors.greenLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.receipt_rounded,
              color: POSColors.greenDark, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _step == 0
                    ? 'Resmi GİB e-Arşiv Fatura Kes'
                    : (_step == 1 ? 'SMS Doğrulama & İmza' : 'Fatura Başarıyla Kesildi'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: POSColors.text,
                ),
              ),
              Text(
                _step == 0
                    ? '0 TL Maliyetle Doğrudan GİB e-Arşiv Portalı'
                    : (_step == 1
                        ? 'GİB Güvenlik Onayı'
                        : 'Fatura resmiyet kazandı'),
                style: const TextStyle(fontSize: 12, color: POSColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildFormStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Alıcı Türü:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              ActionChip(
                label: const Text('Nihai Tüketici (11111111111)'),
                avatar: const Icon(Icons.flash_on_rounded, size: 16, color: POSColors.greenDark),
                backgroundColor: POSColors.greenLight,
                side: BorderSide.none,
                labelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: POSColors.greenDark),
                onPressed: _fillConsumerDefaults,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _identifierCtrl,
                  decoration: const InputDecoration(
                    labelText: 'TCKN / VKN / Kimlik No',
                    hintText: '11 hane TCKN veya 10 hane VKN',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'TCKN/VKN zorunludur';
                    final clean = val.trim();
                    if (clean != '11111111111' && clean.length != 10 && clean.length != 11) {
                      return 'TCKN 11, VKN 10 haneli olmalıdır';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Müşteri Adı / Şirket Unvanı',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Ad Soyad / Unvan zorunludur'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'İl / Şehir',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _districtCtrl,
                  decoration: const InputDecoration(
                    labelText: 'İlçe',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _taxOfficeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vergi Dairesi',
                    hintText: 'Şirketler için',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefon (WhatsApp İçin)',
                    prefixText: '+90 ',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açık Adres',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const Text(
            'Fatura Kalemleri & KDV Dağılımı',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: POSColors.border),
            ),
            child: Column(
              children: [
                ..._invoiceItems.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.name} (${item.quantity.toInt()} adet)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '%${item.vatRate.toInt()} KDV  •  ₺${item.lineTotalWithVat.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('KDV Hariç Matrah:',
                        style: TextStyle(fontSize: 12, color: POSColors.textSecondary)),
                    Text('₺${_totalWithoutVat.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Hesaplanan Toplam KDV:',
                        style: TextStyle(fontSize: 12, color: POSColors.textSecondary)),
                    Text('₺${_totalVat.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Genel Toplam (Ödenecek):',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      '₺${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: POSColors.greenDark),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _submitDraft,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_isLoading
                  ? 'GİB Sistemine Gönderiliyor...'
                  : 'GİB Taslak Fatura Oluştur & SMS İste'),
              style: FilledButton.styleFrom(
                backgroundColor: POSColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sms_rounded, color: Color(0xFF166534), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GİB SMS Onay Kodu Gönderildi!',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                          fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gelir İdaresi Başkanlığı sistemine kayıtlı yetkili cep telefonunuza (${_maskedPhone ?? 'yetkili telefon'}) 6 haneli bir SMS şifresi gönderildi.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF14532D)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _smsCodeCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'GİB SMS Onay Şifresi',
            hintText: '6 haneli şifreyi giriniz',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.password_rounded),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _verifySmsAndSign,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.verified_rounded, size: 20),
            label: Text(_isLoading
                ? 'GİB Tarafından İmzalanıyor...'
                : 'Faturayı Doğrula ve Resmileştir (İmzala)'),
            style: FilledButton.styleFrom(
              backgroundColor: POSColors.green,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                size: 52, color: Color(0xFF15803D)),
          ),
        ),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'e-Arşiv Fatura Resmiyet Kazandı!',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: POSColors.text),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'ETTN / UUID: ${_currentRecord?.gibUuid ?? ''}',
            style: const TextStyle(fontSize: 11, color: POSColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: POSColors.border),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Alıcı:', style: TextStyle(fontSize: 12)),
                  Text(_nameCtrl.text,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Toplam Tutar:', style: TextStyle(fontSize: 12)),
                  Text('₺${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: POSColors.greenDark)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareViaWhatsApp,
                icon: const Icon(Icons.share_rounded, size: 18, color: Color(0xFF16A34A)),
                label: const Text('WhatsApp İle Paylaş'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Tamamla'),
                style: FilledButton.styleFrom(
                  backgroundColor: POSColors.green,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

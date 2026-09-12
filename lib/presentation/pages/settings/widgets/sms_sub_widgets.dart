// lib/presentation/pages/settings/widgets/sms_sub_widgets.dart
// Extracted sub-widgets from sms_settings_sheet.dart
// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/notifications/template_resolver.dart';


class SmsEditTemplateDialog extends StatefulWidget {
  final Map<String, dynamic>? existingTpl;
  final ValueChanged<Map<String, dynamic>> onSave;
  final String channel;

  const SmsEditTemplateDialog({
    required this.existingTpl,
    required this.onSave,
    this.channel = 'sms',
  });

  @override
  State<SmsEditTemplateDialog> createState() => SmsEditTemplateDialogState();
}

class SmsEditTemplateDialogState extends State<SmsEditTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nameCtrl;
  late final TextEditingController templateCtrl;
  late String selectedEvent;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.existingTpl?['name'] ?? '');
    selectedEvent = widget.existingTpl?['id'] ?? 'sale_created';
    if (selectedEvent == 'sale') selectedEvent = 'sale_created';
    if (selectedEvent == 'debt') selectedEvent = 'debt_created';
    if (selectedEvent == 'collection') selectedEvent = 'collection_recorded';
    if (selectedEvent == 'order') selectedEvent = 'order_created';

    final existingWa =
        widget.existingTpl?['whatsapp_template']?.toString().trim();
    final smsTpl = (widget.existingTpl?['sms_template'] ??
            widget.existingTpl?['template'])
        ?.toString()
        .trim();
    final isLegacySms = existingWa == null ||
        existingWa.isEmpty ||
        existingWa == smsTpl ||
        existingWa.startsWith('Merhaba ') ||
        existingWa.startsWith('Merhaba {customer}') ||
        existingWa.startsWith('Sayın {customer}, {id} numaralı');

    final initialTemplate = widget.channel == 'whatsapp'
        ? (!isLegacySms
            ? existingWa
            : (kDefaultWhatsAppTemplates[widget.existingTpl?['id']] ??
                kDefaultWhatsAppTemplates[selectedEvent] ??
                ''))
        : (widget.existingTpl?['sms_template'] ??
            widget.existingTpl?['template'] ??
            '');
    templateCtrl = TextEditingController(text: initialTemplate);
    templateCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    templateCtrl.dispose();
    super.dispose();
  }

  Widget _buildVariableChip(
    TextEditingController controller,
    String token,
    String label,
  ) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, color: POSColors.green),
      ),
      backgroundColor: POSColors.green.withValues(alpha: 0.08),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        final text = controller.text;
        final selection = controller.selection;
        if (selection.start >= 0) {
          final newText = text.replaceRange(
            selection.start,
            selection.end,
            token,
          );
          controller.text = newText;
          controller.selection = TextSelection.collapsed(
            offset: selection.start + token.length,
          );
        } else {
          controller.text = text + token;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existingTpl == null;
    const validEvents = [
      'sale_created',
      'debt_created',
      'collection_recorded',
      'order_created',
      'order_preparing',
      'order_ready',
      'order_delivered',
      'order_cancelled',
      'balance_reminder',
    ];
    if (!validEvents.contains(selectedEvent)) {
      selectedEvent = 'sale_created';
    }

    final isWhatsApp = widget.channel == 'whatsapp';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isWhatsApp
                  ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                  : POSColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isWhatsApp ? Icons.chat_rounded : Icons.sms_rounded,
              color: isWhatsApp ? const Color(0xFF16A34A) : POSColors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isWhatsApp
                  ? (isNew ? 'Yeni WhatsApp Şablonu' : 'WhatsApp Şablonunu Düzenle')
                  : (isNew ? 'Yeni SMS Şablonu' : 'SMS Şablonunu Düzenle'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isWhatsApp
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isWhatsApp
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isWhatsApp ? Icons.info_outline_rounded : Icons.speed_rounded,
                      size: 16,
                      color: isWhatsApp ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isWhatsApp
                            ? 'WhatsApp mesajlarında karakter sınırı yoktur. Emojiler, satır başları, *kalın* ve _italik_ metin serbestçe kullanılabilir.'
                            : 'Standart SMS sınırı 160 karakterdir. Fazla karakterler ek SMS olarak ücretlendirilebilir.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isWhatsApp ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Şablon Adı',
                  prefixIcon: const Icon(Icons.title_rounded, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Şablon adı gerekli' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedEvent,
                style: const TextStyle(fontSize: 14, color: Colors.black),
                decoration: InputDecoration(
                  labelText: 'Tetikleyici Durum (Olay)',
                  prefixIcon: const Icon(Icons.flash_on_rounded, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'sale_created',
                    child: Text('Satış Tamamlandığında'),
                  ),
                  DropdownMenuItem(
                    value: 'debt_created',
                    child: Text('Borç Eklendiğinde'),
                  ),
                  DropdownMenuItem(
                    value: 'collection_recorded',
                    child: Text('Tahsilat Yapıldığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_created',
                    child: Text('Sipariş Alındığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_preparing',
                    child: Text('Sipariş Hazırlanmaya Başladığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_ready',
                    child: Text('Sipariş Hazırlandığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_delivered',
                    child: Text('Sipariş Teslim Edildiğinde'),
                  ),
                  DropdownMenuItem(
                    value: 'order_cancelled',
                    child: Text('Sipariş İptal Edildiğinde'),
                  ),
                  DropdownMenuItem(
                    value: 'balance_reminder',
                    child: Text('Bakiye Hatırlatması Gönderildiğinde'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedEvent = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: templateCtrl,
                maxLines: isWhatsApp ? 6 : 3,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: isWhatsApp
                      ? 'WhatsApp Mesaj Şablonu (Karakter Sınırı Yok)'
                      : 'SMS Mesaj Şablonu',
                  hintText: isWhatsApp
                      ? 'örn:\n🧾 *Sipariş Bilgisi*\nSayın *{customer}*,\n{id} numaralı siparişiniz alındı.\n*{business}*'
                      : 'örn: Sn. {customer}, {amount} TL ödemeniz alındı.',
                  prefixIcon: Icon(
                    isWhatsApp ? Icons.chat_bubble_outline_rounded : Icons.text_snippet_rounded,
                    size: 18,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Şablon içeriği gerekli' : null,
              ),
              if (!isWhatsApp) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${templateCtrl.text.length} / 160 karakter (1 SMS)',
                    style: TextStyle(
                      fontSize: 11,
                      color: templateCtrl.text.length > 160
                          ? Colors.red[700]
                          : POSColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kullanılabilir Değişkenler:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: POSColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildVariableChip(templateCtrl, '{customer}', 'Müşteri'),
                  _buildVariableChip(templateCtrl, '{amount}', 'Tutar'),
                  _buildVariableChip(templateCtrl, '{debt}', 'Borç/Bakiye'),
                  _buildVariableChip(templateCtrl, '{id}', 'Fiş/İşlem No'),
                  _buildVariableChip(templateCtrl, '{business}', 'İşletme Adı'),
                  _buildVariableChip(templateCtrl, '{date}', 'İşlem Tarihi'),
                  _buildVariableChip(templateCtrl, '{items}', 'Ürünler'),
                  _buildVariableChip(templateCtrl, '{phone}', 'Telefon'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'İptal',
            style: TextStyle(color: POSColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final result = Map<String, dynamic>.from(widget.existingTpl ?? {});
              result['id'] = selectedEvent;
              result['name'] = nameCtrl.text.trim();
              if (isWhatsApp) {
                result['whatsapp_template'] = templateCtrl.text.trim();
                result['whatsapp_enabled'] =
                    widget.existingTpl?['whatsapp_enabled'] ?? true;
                result['sms_template'] ??= widget.existingTpl?['sms_template'] ??
                    widget.existingTpl?['template'] ??
                    '';
                result['template'] = result['sms_template'];
              } else {
                result['sms_template'] = templateCtrl.text.trim();
                result['template'] = templateCtrl.text.trim();
                result['sms_enabled'] = widget.existingTpl?['sms_enabled'] ??
                    widget.existingTpl?['enabled'] ??
                    true;
                result['enabled'] = result['sms_enabled'];
                result['whatsapp_template'] ??=
                    widget.existingTpl?['whatsapp_template'] ?? '';
              }
              widget.onSave(result);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isWhatsApp ? const Color(0xFF16A34A) : POSColors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class SmsChannelStatusChip extends StatelessWidget {
  const SmsChannelStatusChip({
    required this.icon,
    required this.label,
    required this.ready,
  });

  final IconData icon;
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: ready ? const Color(0xFF86EFAC) : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class SmsOperationsSectionLabel extends StatelessWidget {
  const SmsOperationsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: POSColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      );
}

class SmsMessageActionCard extends StatelessWidget {
  const SmsMessageActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String actionLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: enabled ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: POSColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: POSColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: POSColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        actionLabel,
                        style: TextStyle(
                          color: enabled ? color : POSColors.textDisabled,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: enabled ? color : POSColors.textDisabled,
                ),
              ],
            ),
          ),
        ),
      );
}

class SmsMessageInfoBanner extends StatelessWidget {
  const SmsMessageInfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: POSColors.amberLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: POSColors.amber.withValues(alpha: .3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: POSColors.amberDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: POSColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
}

class SmsBulkAnnouncementDialog extends StatefulWidget {
  const SmsBulkAnnouncementDialog({required this.recipientCount});

  final int recipientCount;

  @override
  State<SmsBulkAnnouncementDialog> createState() =>
      SmsBulkAnnouncementDialogState();
}

class SmsBulkAnnouncementDialogState extends State<SmsBulkAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final msgCtrl = TextEditingController();
  bool permissionConfirmed = false;

  @override
  void dispose() {
    msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tanıtım mesajı oluştur'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDE9FE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: Color(0xFF7C3AED),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${widget.recipientCount} telefon numarası kayıtlı müşteri',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SmsDialogChannelBadge(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: msgCtrl,
                  minLines: 5,
                  maxLines: 8,
                  maxLength: 480,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Mesaj',
                    hintText:
                        'Merhaba {customer}, bu haftaya özel ürünlerimizi inceleyebilirsiniz.',
                    helperText:
                        '{customer} yazarsanız her müşterinin adı otomatik eklenir.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty
                      ? 'Mesaj metni zorunludur.'
                      : null,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    msgCtrl.text.trim().isEmpty
                        ? 'Önizleme burada görünecek.'
                        : msgCtrl.text.trim().replaceAll(
                              '{customer}',
                              'Ayşe Hanım',
                            ),
                    style: const TextStyle(
                      color: POSColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: permissionConfirmed,
                  onChanged: (value) =>
                      setState(() => permissionConfirmed = value ?? false),
                  title: const Text(
                    'Yalnız iletişim izni bulunan müşterilere gönderdiğimi onaylıyorum.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Vazgeç',
            style: TextStyle(color: POSColors.textSecondary),
          ),
        ),
        FilledButton.icon(
          onPressed: permissionConfirmed
              ? () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.pop(context, msgCtrl.text.trim());
                  }
                }
              : null,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text('${widget.recipientCount} kişiye gönder'),
        ),
      ],
    );
  }
}

class SmsDialogChannelBadge extends StatelessWidget {
  const SmsDialogChannelBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFDDD6FE)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sms_rounded, size: 14, color: Color(0xFF7C3AED)),
            SizedBox(width: 4),
            Text(
              'SMS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF7C3AED),
              ),
            ),
          ],
        ),
      );
}


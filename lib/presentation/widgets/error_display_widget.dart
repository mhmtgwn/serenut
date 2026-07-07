// lib/presentation/widgets/error_display_widget.dart
// Serenut OS — Centralized Error Display Dialog & Widget
// Blueprint: error_code_catalog.md

import 'package:flutter/material.dart';

class ErrorCatalog {
  static const Map<String, String> messages = {
    'AUTH001': 'E-posta veya şifre hatalı. Lütfen tekrar deneyin.',
    'AUTH002': 'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.',
    'AUTH003': 'Hesabınız askıya alınmıştır. Destek ile iletişime geçin.',
    'AUTH004': 'Çok fazla hatalı giriş denemesi. 15 dakika bekleyin.',
    'AUTH005': 'Bu işlem için yetkiniz bulunmuyor.',
    'LICENSE101': 'Girdiğiniz lisans anahtarı geçerli değil.',
    'LICENSE102': 'Lisansınızın süresi dolmuştur. Lütfen yenileyin.',
    'LICENSE103': 'Cihaz limitinize ulaştınız. Portaldan eski bir cihazı kaldırın.',
    'LICENSE104': 'Bu ay cihaz değişim hakkınızı doldurdunuz.',
    'LICENSE105': 'Bu cihaz başka bir hesaba kayıtlı. Desteğe başvurun.',
    'LICENSE106': 'Ödemeniz alınamadı. Lütfen ödeme bilgilerinizi güncelleyin.',
    'SYNC201': 'Mükerrer istek tespit edildi.',
    'SYNC202': 'Veri senkronizasyonunda hata oluştu. Destek kodu: SYNC202',
    'SYNC203': 'Senkronizasyon geçici olarak duraklatıldı. Verileriniz güvende.',
    'SYNC204': 'Veri çakışması tespit edildi. Sunucu değeri esas alındı.',
    'PAYMENT301': 'Kartınız reddedildi. Lütfen farklı bir ödeme yöntemi deneyin.',
    'PAYMENT302': 'Kartınızda yeterli bakiye bulunmuyor.',
    'PAYMENT303': 'Güvenli ödeme doğrulaması tamamlanamadı. Tekrar deneyin.',
    'PAYMENT304': 'Ödeme işlemi zaman aşımına uğradı. Lütfen tekrar deneyin.',
    'PAYMENT305': 'Ödeme anlaşmazlığı nedeniyle hesabınız geçici olarak askıya alındı.',
    'COMPANY401': 'Bu şubede aktif cihaz var. Önce cihazı kaldırın.',
    'COMPANY402': 'Hesap silme talebiniz alındı. 7 gün içinde iptal edebilirsiniz.',
    'COMPANY403': 'Deneme süresini yalnızca destek ekibi uzatabilir.',
    'DEVICE501': 'Bu cihaz lisansınıza bağlı değil. Portaldan ekleyin.',
    'DEVICE502': 'Bu cihaz güvenlik nedeniyle engellendi. Desteğe başvurun.',
    'DEVICE503': 'Cihaz saati geçersiz. Sistem saatini doğrulayın.',
  };

  static String getMessage(String code, [String? fallback]) {
    return messages[code] ?? fallback ?? 'Beklenmedik bir hata oluştu (Hata Kodu: $code).';
  }
}

class ErrorDisplayWidget extends StatelessWidget {
  final String errorCode;
  final String? customMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  const ErrorDisplayWidget({
    super.key,
    required this.errorCode,
    this.customMessage,
    this.onRetry,
    this.onClose,
  });

  /// Displays the error in a beautiful Material dialog.
  static Future<void> showAsDialog(
    BuildContext context, {
    required String errorCode,
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: const Color(0xFF1E293B), // Slate 800
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 56,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sistem Uyarısı',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ErrorCatalog.getMessage(errorCode, customMessage),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hata Kodu: $errorCode',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'Kapat',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onRetry();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981), // Emerald 500
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = ErrorCatalog.getMessage(errorCode, customMessage);
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF7F1D1D), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hata Kodu: $errorCode',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onClose != null)
                      TextButton(
                        onPressed: onClose,
                        child: const Text('Kapat', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      ),
                    if (onRetry != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: const Text('Yenile', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

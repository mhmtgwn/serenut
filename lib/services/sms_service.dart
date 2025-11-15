import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';
import 'database_service.dart';

class SmsService {
  Future<bool> sendSms(String phone, String message, {int? orderId}) async {
    try {
      // SMS uygulamasını aç (url_launcher ile)
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': message},
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        await _logSms(phone, message, 'opened', orderId);
        return true;
      } else {
        await _logSms(phone, message, 'failed', orderId);
        return false;
      }
    } catch (e) {
      await _logSms(phone, message, 'failed', orderId);
      return false;
    }
  }

  Future<void> _logSms(
    String phone,
    String message,
    String status,
    int? orderId,
  ) async {
    final db = await DatabaseService.database;
    await db.insert('sms_log', {
      'phone': phone,
      'message': message,
      'status': status,
      'order_id': orderId,
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  // SMS Şablonları
  String orderConfirmation(String customerName, String orderNumber) {
    return '''Sayın $customerName,
Siparişiniz alındı.
Sipariş No: $orderNumber
Teşekkür ederiz.''';
  }

  String orderReady(String customerName, String orderNumber) {
    return '''Sayın $customerName,
Siparişiniz hazır!
Sipariş No: $orderNumber''';
  }

  String orderOnTheWay(String customerName, String orderNumber) {
    return '''Sayın $customerName,
Siparişiniz yola çıktı!
Sipariş No: $orderNumber''';
  }

  String orderDelivered(String customerName, String orderNumber) {
    return '''Sayın $customerName,
Siparişiniz teslim edildi.
Sipariş No: $orderNumber
Afiyet olsun!''';
  }

  // Otomatik SMS gönder
  Future<bool> sendOrderSms(Order order, String status) async {
    String message;
    switch (status) {
      case 'pending':
        message = orderConfirmation(order.customerName, order.orderNumber);
        break;
      case 'ready':
        message = orderReady(order.customerName, order.orderNumber);
        break;
      case 'ontheway':
        message = orderOnTheWay(order.customerName, order.orderNumber);
        break;
      case 'delivered':
        message = orderDelivered(order.customerName, order.orderNumber);
        break;
      default:
        return false;
    }

    return await sendSms(order.customerPhone, message, orderId: order.id);
  }
}

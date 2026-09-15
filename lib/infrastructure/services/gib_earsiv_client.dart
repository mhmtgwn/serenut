// lib/infrastructure/services/gib_earsiv_client.dart
// Serenut OS — GİB e-Arşiv Portalı Doğrudan İletişim İstemcisi
// 0 TL Maliyetli, GİB e-Arşiv Resmi Web Servisi Protokolü

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';

class GibAuthException implements Exception {
  final String message;
  GibAuthException(this.message);
  @override
  String toString() => 'GİB Giriş Hatası: $message';
}

class GibInvoiceException implements Exception {
  final String message;
  GibInvoiceException(this.message);
  @override
  String toString() => 'GİB Fatura Hatası: $message';
}

class GibEArsivClient {
  final http.Client _httpClient;
  bool isTestMode;

  String? _token;
  DateTime? _tokenExpiresAt;

  GibEArsivClient({
    http.Client? httpClient,
    this.isTestMode = false,
  }) : _httpClient = httpClient ?? http.Client();

  String get _baseUrl => isTestMode
      ? 'https://earsivportaltest.efatura.gov.tr/earsiv-services/dispatch'
      : 'https://earsivportal.efatura.gov.tr/earsiv-services/dispatch';

  String get _referrerUrl => isTestMode
      ? 'https://earsivportaltest.efatura.gov.tr/'
      : 'https://earsivportal.efatura.gov.tr/';

  Map<String, String> _headers(String? token) => {
        'Accept': '*/*',
        'Accept-Language': 'tr,en-US;q=0.9,en;q=0.8',
        'Cache-Control': 'no-cache',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Pragma': 'no-cache',
        'Referer': _referrerUrl,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      };

  /// 1. GİB e-Arşiv Portalına Giriş Yap ve Token Al
  Future<String> login({
    required String username,
    required String password,
  }) async {
    final now = DateTime.now();
    if (_token != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.isAfter(now.add(const Duration(minutes: 2)))) {
      return _token!;
    }

    final callid = const Uuid().v4().replaceAll('-', '');
    final jpMap = {
      'assoscmd': isTestMode ? 'ANONIM_GIRIS' : 'LOGIN',
      'userid': username.trim(),
      'sifre': password.trim(),
      'parola': '1',
    };

    final body = {
      'cmd': 'EARSIV_PORTAL_GIRIS',
      'callid': callid,
      'pageName': 'RG_GIRIS',
      'token': '',
      'jp': jsonEncode(jpMap),
    };

    try {
      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: _headers(null),
        body: body,
      );

      if (response.statusCode != 200) {
        throw GibAuthException(
            'Sunucu yanıt vermedi (HTTP ${response.statusCode})');
      }

      final resJson = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;

      if (resJson['error'] != null) {
        throw GibAuthException(resJson['error'].toString());
      }

      final data = resJson['data'] as Map<String, dynamic>?;
      final token = data?['token'] as String?;

      if (token == null || token.isEmpty) {
        final msg = resJson['messages']?.toString() ??
            'Giriş yapılamadı. Kullanıcı kodu veya şifre hatalı.';
        throw GibAuthException(msg);
      }

      _token = token;
      _tokenExpiresAt = DateTime.now().add(const Duration(minutes: 25));
      debugPrint('[GibEArsivClient] GİB Girişi Başarılı. Token: ${_token?.substring(0, 8)}...');
      return token;
    } catch (e) {
      if (e is GibAuthException) rethrow;
      throw GibAuthException('GİB portalına bağlanılamadı: $e');
    }
  }

  /// 2. GİB Taslak Fatura Oluştur
  Future<String> createDraftInvoice({
    required String token,
    required GibInvoiceRecipient recipient,
    required List<GibInvoiceItem> items,
    required double totalWithoutVat,
    required double totalVat,
    required double totalAmount,
    GibInvoiceType invoiceType = GibInvoiceType.satis,
    String? note,
    String? predefinedUuid,
  }) async {
    final uuid = predefinedUuid ?? const Uuid().v4().toLowerCase();
    final now = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    final isConsumer = recipient.type == GibRecipientType.consumer ||
        recipient.identifier == '11111111111';

    final nameParts = recipient.titleOrName.trim().split(' ');
    final firstName = isConsumer
        ? (nameParts.isNotEmpty ? nameParts.first : 'Nihai')
        : (recipient.identifier.length == 11
            ? (nameParts.isNotEmpty ? nameParts.first : '')
            : '');
    final lastName = isConsumer
        ? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'Tüketici')
        : (recipient.identifier.length == 11
            ? (nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '')
            : '');
    final unvan = recipient.identifier.length == 10
        ? recipient.titleOrName
        : '';

    final malHizmetTable = items.map((item) {
      return {
        'malHizmet': item.name,
        'miktar': item.quantity,
        'birim': item.unit,
        'birimFiyat': item.unitPrice.toStringAsFixed(2),
        'fiyat': (item.quantity * item.unitPrice).toStringAsFixed(2),
        'iskontoOrani': 0,
        'iskontoTutari': item.discountAmount.toStringAsFixed(2),
        'iskontoNedeni': '',
        'malHizmetTutari': item.lineTotalWithoutVat.toStringAsFixed(2),
        'kdvOrani': item.vatRate.toInt(),
        'kdvTutari': item.vatAmount.toStringAsFixed(2),
        'vergiOrani': 0,
      };
    }).toList();

    final jpMap = {
      'faturaUuid': uuid,
      'belgeNumarasi': '',
      'faturaTarihi': dateStr,
      'saat': timeStr,
      'paraBirimi': 'TRY',
      'dovizKuru': '0',
      'faturaTipi': invoiceType.code,
      'hangiTip': '5000/30000',
      'vknTckn': recipient.identifier,
      'aliciUnvan': unvan,
      'aliciAdi': firstName,
      'aliciSoyadi': lastName,
      'binaAdi': '',
      'binaNo': '',
      'kapiNo': '',
      'kasabaKoyu': recipient.district.isNotEmpty ? recipient.district : '',
      'vergiDairesi': recipient.taxOffice,
      'ulke': 'Türkiye',
      'bulvarCaddeSokak': recipient.address,
      'mahalleSemtIlce': recipient.district,
      'sehir': recipient.city.isNotEmpty ? recipient.city : 'Türkiye',
      'postaKodu': '',
      'tel': recipient.phone ?? '',
      'fax': '',
      'eposta': recipient.email ?? '',
      'websitesi': '',
      'iadeTable': [],
      'ozelMatrahTutari': '0',
      'ozelMatrahOrani': 0,
      'ozelMatrahVergiTutari': '0',
      'vergiCesidi': '0',
      'malHizmetTable': malHizmetTable,
      'tip': 'İskonto',
      'matrah': totalWithoutVat.toStringAsFixed(2),
      'malhizmetToplamTutari': totalWithoutVat.toStringAsFixed(2),
      'toplamIskonto': '0.00',
      'hesaplanankdv': totalVat.toStringAsFixed(2),
      'vergilerDahilToplamTutar': totalAmount.toStringAsFixed(2),
      'odenecekTutar': totalAmount.toStringAsFixed(2),
      'not': note?.trim() ?? 'Serenut OS ile düzenlenmiştir.',
      'siparisNumarasi': '',
      'siparisTarihi': '',
      'irsaliyeNumarasi': '',
      'irsaliyeTarihi': '',
      'fisNo': '',
      'fisTarihi': '',
      'fisSaati': ' ',
      'fisTipi': ' ',
      'zRaporNo': '',
      'okcSeriNo': '',
    };

    final callid = const Uuid().v4().replaceAll('-', '');
    final body = {
      'cmd': 'EARSIV_PORTAL_FATURA_OLUSTUR',
      'callid': callid,
      'pageName': 'RG_BASITTASLAKLAR',
      'token': token,
      'jp': jsonEncode(jpMap),
    };

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: _headers(token),
      body: body,
    );

    if (response.statusCode != 200) {
      throw GibInvoiceException(
          'Fatura oluşturulamadı (HTTP ${response.statusCode})');
    }

    final resJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (resJson['error'] != null) {
      throw GibInvoiceException(resJson['error'].toString());
    }

    final data = resJson['data']?.toString() ?? '';
    if (data.contains('başarıyla') || resJson['metadata'] != null) {
      debugPrint('[GibEArsivClient] Fatura Taslağı Oluşturuldu: $uuid');
      return uuid;
    }

    throw GibInvoiceException('GİB Fatura Taslak Yanıtı: $data');
  }

  /// 3. GİB'den Yetkili Cep Telefonuna SMS Doğrulama Kodu İste
  Future<String> requestSmsCode({required String token}) async {
    final callid = const Uuid().v4().replaceAll('-', '');
    final jpMap = {
      'cepiptal': false,
    };

    final body = {
      'cmd': 'EARSIV_PORTAL_SMSSIFRE_GONDER',
      'callid': callid,
      'pageName': 'RG_SMSONAY',
      'token': token,
      'jp': jsonEncode(jpMap),
    };

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: _headers(token),
      body: body,
    );

    if (response.statusCode != 200) {
      throw GibInvoiceException(
          'SMS kodu istenemedi (HTTP ${response.statusCode})');
    }

    final resJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (resJson['error'] != null) {
      throw GibInvoiceException(resJson['error'].toString());
    }

    final data = resJson['data'] as Map<String, dynamic>?;
    final phone = data?['ceptel']?.toString() ?? '';
    debugPrint('[GibEArsivClient] GİB SMS Şifresi Gönderildi ($phone)');
    return phone;
  }

  /// 4. SMS Şifresini Doğrula ve Faturayı İmzala (Resmileştir)
  Future<bool> verifySmsAndSign({
    required String token,
    required String smsCode,
    required String invoiceUuid,
  }) async {
    final callid = const Uuid().v4().replaceAll('-', '');
    final jpMap = {
      'smsSifre': smsCode.trim(),
      'imzalanacaklar': [
        {'faturaUuid': invoiceUuid},
      ],
    };

    final body = {
      'cmd': 'EARSIV_PORTAL_SMSSIFRE_DOGRULA',
      'callid': callid,
      'pageName': 'RG_SMSONAY',
      'token': token,
      'jp': jsonEncode(jpMap),
    };

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: _headers(token),
      body: body,
    );

    if (response.statusCode != 200) {
      throw GibInvoiceException(
          'SMS doğrulanamadı (HTTP ${response.statusCode})');
    }

    final resJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (resJson['error'] != null) {
      throw GibInvoiceException(resJson['error'].toString());
    }

    final data = resJson['data']?.toString() ?? '';
    if (data.contains('başarıyla') || data.contains('imzalandı')) {
      debugPrint('[GibEArsivClient] Fatura Resmi Olarak İmzalandı: $invoiceUuid');
      return true;
    }

    if (resJson['messages'] != null) {
      throw GibInvoiceException(resJson['messages'].toString());
    }

    return true;
  }

  /// 5. İmzalanmış Resmi Faturanın HTML Çıktısını Al (Görüntüleme & Fiş Yazdırma İçin)
  Future<String> getInvoiceHtml({
    required String token,
    required String invoiceUuid,
  }) async {
    final callid = const Uuid().v4().replaceAll('-', '');
    final jpMap = {
      'ettn': invoiceUuid,
      'onayDurumu': 'Onaylandı',
    };

    final body = {
      'cmd': 'EARSIV_PORTAL_FATURA_GOSTER',
      'callid': callid,
      'pageName': 'RG_TASLAKLAR',
      'token': token,
      'jp': jsonEncode(jpMap),
    };

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: _headers(token),
      body: body,
    );

    if (response.statusCode != 200) {
      throw GibInvoiceException(
          'Fatura HTML içeriği alınamadı (HTTP ${response.statusCode})');
    }

    final resJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (resJson['error'] != null) {
      throw GibInvoiceException(resJson['error'].toString());
    }

    final html = resJson['data']?.toString() ?? '';
    return html;
  }

  /// 6. Faturayı İptal Et
  Future<bool> cancelInvoice({
    required String token,
    required String invoiceUuid,
    required String reason,
  }) async {
    final callid = const Uuid().v4().replaceAll('-', '');
    final jpMap = {
      'silinecekler': [
        {'faturaUuid': invoiceUuid},
      ],
      'aciklama': reason.trim(),
    };

    final body = {
      'cmd': 'EARSIV_PORTAL_FATURA_SIL',
      'callid': callid,
      'pageName': 'RG_TASLAKLAR',
      'token': token,
      'jp': jsonEncode(jpMap),
    };

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: _headers(token),
      body: body,
    );

    if (response.statusCode != 200) {
      throw GibInvoiceException(
          'Fatura iptal edilemedi (HTTP ${response.statusCode})');
    }

    final resJson =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (resJson['error'] != null) {
      throw GibInvoiceException(resJson['error'].toString());
    }

    return true;
  }
}

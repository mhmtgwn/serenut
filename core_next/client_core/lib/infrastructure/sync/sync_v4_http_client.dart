// core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/sync_dtos.dart';
import '../../domain/models/sync_mutation.dart';

typedef TokenProvider = Future<String?> Function();
typedef UnauthorizedRefreshHandler = Future<bool> Function();

/// Serenut OS Sync V4 / Protocol 6 İzole HTTP İstemcisi.
/// 
/// Tamamen ağdan soyutlanabilir ve `MockClient` ile test edilebilir mimaridedir.
class SyncV4HttpClient {
  static const int protocolVersion = 6;

  final String baseUrl;
  final String deviceActivationId;
  final String deviceId;
  final TokenProvider? tokenProvider;
  final UnauthorizedRefreshHandler? onUnauthorized;
  final http.Client client;
  final Duration timeout;

  SyncV4HttpClient({
    required this.baseUrl,
    required this.deviceActivationId,
    required this.deviceId,
    this.tokenProvider,
    this.onUnauthorized,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : client = client ?? http.Client();

  /// Başlıkları protokol ve kimlik bilgileriyle derler.
  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'x-sync-protocol-version': '$protocolVersion',
      'x-device-activation-id': deviceActivationId,
      'x-device-id': deviceId,
    };

    if (tokenProvider != null) {
      final token = await tokenProvider!();
      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Bekleyen mutasyonları toplu (en fazla 100) olarak sunucuya iter (`POST /api/v4/sync/push`).
  Future<SyncPushResponseDto> push(List<SyncMutation> mutations) async {
    if (mutations.isEmpty) {
      return const SyncPushResponseDto();
    }
    if (mutations.length > 100) {
      throw ArgumentError('Tek seferde en fazla 100 mutasyon push edilebilir.');
    }

    final uri = Uri.parse('$baseUrl/push');
    final payload = {
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
      'mutations': mutations.map((m) => m.toServerMutationDto()).toList(),
    };

    return await _execute<SyncPushResponseDto>(() async {
      final headers = await _buildHeaders();
      final response = await client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(timeout);

      final decoded = _handleResponse(response);
      if (decoded is! Map<String, dynamic>) {
        throw const SyncFormatException('Push yanıtı geçerli bir JSON nesnesi olmalıdır.');
      }
      return SyncPushResponseDto.fromJson(decoded);
    });
  }

  /// Sunucudaki son revizyondan sonraki değişiklikleri çeker (`GET /api/v4/sync/pull`).
  Future<SyncPullResponseDto> pull({int cursor = 0, int limit = 200}) async {
    final queryParams = {
      'cursor': '$cursor',
      'limit': '$limit',
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
    };
    final uri = Uri.parse('$baseUrl/pull').replace(queryParameters: queryParams);

    return await _execute<SyncPullResponseDto>(() async {
      final headers = await _buildHeaders();
      final response = await client.get(uri, headers: headers).timeout(timeout);

      final decoded = _handleResponse(response);
      if (decoded is! Map<String, dynamic>) {
        throw const SyncFormatException('Pull yanıtı geçerli bir JSON nesnesi olmalıdır.');
      }
      return SyncPullResponseDto.fromJson(decoded);
    });
  }

  /// Yeni cihaz veya boş veritabanı için ilk snapshot yedeğini çeker (`GET /api/v4/sync/bootstrap`).
  Future<SyncBootstrapResponseDto> bootstrap() async {
    final queryParams = {
      'device_activation_id': deviceActivationId,
      'device_id': deviceId,
    };
    final uri = Uri.parse('$baseUrl/bootstrap').replace(queryParameters: queryParams);

    return await _execute<SyncBootstrapResponseDto>(() async {
      final headers = await _buildHeaders();
      final response = await client.get(uri, headers: headers).timeout(timeout);

      final decoded = _handleResponse(response);
      if (decoded is! Map<String, dynamic>) {
        throw const SyncFormatException('Bootstrap yanıtı geçerli bir JSON nesnesi olmalıdır.');
      }
      return SyncBootstrapResponseDto.fromJson(decoded);
    });
  }

  /// HTTP durum kodunu denetler ve gövdeyi JSON olarak çözer.
  dynamic _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw SyncFormatException('Geçersiz JSON yanıtı: ${response.body}');
      }
    }

    final errorMessage = (decoded is Map && decoded['error'] != null)
        ? decoded['error'].toString()
        : (decoded is Map && decoded['message'] != null)
            ? decoded['message'].toString()
            : 'HTTP ${response.statusCode}';

    switch (response.statusCode) {
      case 200:
      case 201:
        return decoded;
      case 400:
        throw SyncBadRequestException(errorMessage);
      case 401:
        throw SyncUnauthorizedException(errorMessage);
      case 403:
        throw SyncForbiddenException(errorMessage);
      case 409:
        final errorCode = (decoded is Map && decoded['error'] != null)
            ? decoded['error'].toString()
            : null;
        throw SyncConflictException(errorMessage, errorCode: errorCode);
      case 426:
        final reqVer = (decoded is Map && decoded['required_version'] != null)
            ? (decoded['required_version'] as num).toInt()
            : protocolVersion;
        throw SyncProtocolUpgradeRequiredException(
          requiredVersion: reqVer,
          message: errorMessage,
        );
      case 500:
      case 502:
      case 503:
      case 504:
        throw SyncServerException(errorMessage, response.statusCode);
      default:
        throw SyncServerException(errorMessage, response.statusCode);
    }
  }

  /// Ağ, zaman aşımı ve format hatalarını güvenli tipte yakalar.
  Future<T> _execute<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SyncUnauthorizedException {
      if (onUnauthorized != null) {
        try {
          final refreshed = await onUnauthorized!();
          if (refreshed) {
            return await action();
          }
        } catch (refreshErr) {
          debugPrint('[SyncHttpClient] Token refresh failed: $refreshErr');
        }
      }
      rethrow;
    } on TimeoutException {
      throw const SyncTimeoutException();
    } on http.ClientException catch (e) {
      throw SyncNetworkException('Ağ bağlantı hatası: ${e.message}');
    } on FormatException catch (e) {
      throw SyncFormatException('Veri format hatası: ${e.message}');
    } on SyncException {
      rethrow;
    } catch (e) {
      throw SyncNetworkException('Bilinmeyen istemci hatası: $e');
    }
  }

  void close() {
    client.close();
  }
}

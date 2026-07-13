// lib/infrastructure/network/api_client.dart
// Serenut Platform — API Network Client
// Standardized client layer with error mapper, idempotency keys, and mock response interceptors.
// Created: 04 Jul 2026

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/environment.dart';

class ApiResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const ApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  dynamic get json => jsonDecode(body);
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  const ApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class ApiClient {
  final http.Client _client;
  final EnvironmentConfig _config;
  String? _jwtToken;
  
  // Callbacks for dynamic token refresh and session expiration
  Future<bool> Function()? onTokenExpired;
  void Function()? onSessionExpired;
  Future<bool>? _refreshFuture;

  // Custom mock handler function for testing/development
  ApiResponse Function(http.BaseRequest request)? mockHandler;

  ApiClient({
    http.Client? httpClient,
    EnvironmentConfig? config,
  })  : _client = httpClient ?? http.Client(),
        _config = config ?? EnvironmentConfig.current;

  /// Sets the authentication JWT token.
  void setJwtToken(String? token) {
    _jwtToken = token;
  }

  /// Returns the current JWT token (read-only).
  String? get jwtToken => _jwtToken;

  /// Helper to build request headers.
  Map<String, String> _buildHeaders({String? idempotencyKey}) {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-schema-version': '1',
    };

    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    if (idempotencyKey != null) {
      headers['Idempotency-Key'] = idempotencyKey;
    }

    return headers;
  }

  /// Sends a request. Automatically processes mock hooks or proceeds with HTTP.
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    String cleanPath = path;
    if (cleanPath.startsWith('/api/v1') && _config.apiBaseUrl.endsWith('/api/v1')) {
      cleanPath = cleanPath.substring(7);
    }
    final uri = Uri.parse('${_config.apiBaseUrl}$cleanPath');
    final headers = _buildHeaders(idempotencyKey: idempotencyKey);
    final String? bodyString = body != null ? jsonEncode(body) : null;

    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    if (bodyString != null) {
      request.body = bodyString;
    }

    // 1. Hook Mock Handler if configured (useful for development/testing)
    if (mockHandler != null) {
      final mockRes = mockHandler!(request);
      if (!mockRes.isSuccess) {
        throw ApiException(
          'HTTP Request failed with status code ${mockRes.statusCode}',
          statusCode: mockRes.statusCode,
          responseBody: mockRes.body,
        );
      }
      return mockRes;
    }

    // 2. Perform actual network call
    try {
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      
      final apiResponse = ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        headers: response.headers,
      );

      // Handle transparent JWT token refresh on 401s
      if (response.statusCode == 401 && !path.startsWith('/auth/') && onTokenExpired != null) {
        _refreshFuture ??= onTokenExpired!();
        final success = await _refreshFuture!;
        _refreshFuture = null; // reset for next time

        if (success) {
          final newHeaders = _buildHeaders(idempotencyKey: idempotencyKey);
          final retryRequest = http.Request(method, uri);
          retryRequest.headers.addAll(newHeaders);
          if (bodyString != null) {
            retryRequest.body = bodyString;
          }

          final retryStreamed = await _client.send(retryRequest);
          final retryResponse = await http.Response.fromStream(retryStreamed);
          
          final retryApiResponse = ApiResponse(
            statusCode: retryResponse.statusCode,
            body: retryResponse.body,
            headers: retryResponse.headers,
          );

          if (!retryApiResponse.isSuccess) {
            throw ApiException(
              'HTTP Request failed with status code ${retryResponse.statusCode}',
              statusCode: retryResponse.statusCode,
              responseBody: retryResponse.body,
            );
          }
          return retryApiResponse;
        } else {
          if (onSessionExpired != null) {
            onSessionExpired!();
          }
          throw ApiException('Session expired', statusCode: 401);
        }
      }

      if (!apiResponse.isSuccess) {
        throw ApiException(
          'HTTP Request failed with status code ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }

      return apiResponse;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error during request: $e');
    }
  }

  /// Helper for GET requests.
  Future<ApiResponse> get(String path) => send('GET', path);

  /// Helper for POST requests.
  Future<ApiResponse> post(String path, Map<String, dynamic> body, {String? idempotencyKey}) =>
      send('POST', path, body: body, idempotencyKey: idempotencyKey);

  /// Helper for PUT requests.
  Future<ApiResponse> put(String path, Map<String, dynamic> body, {String? idempotencyKey}) =>
      send('PUT', path, body: body, idempotencyKey: idempotencyKey);

  /// Helper for DELETE requests.
  Future<ApiResponse> delete(String path) => send('DELETE', path);

  void dispose() {
    _client.close();
  }
}

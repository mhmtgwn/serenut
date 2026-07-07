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
  Map<String, String> _buildHeaders({bool includeIdempotency = false}) {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    if (includeIdempotency) {
      headers['Idempotency-Key'] = const Uuid().v4();
    }

    return headers;
  }

  /// Sends a request. Automatically processes mock hooks or proceeds with HTTP.
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool includeIdempotency = false,
  }) async {
    final uri = Uri.parse('${_config.apiBaseUrl}$path');
    final headers = _buildHeaders(includeIdempotency: includeIdempotency);
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
  Future<ApiResponse> post(String path, Map<String, dynamic> body, {bool idempotency = true}) =>
      send('POST', path, body: body, includeIdempotency: idempotency);

  /// Helper for PUT requests.
  Future<ApiResponse> put(String path, Map<String, dynamic> body, {bool idempotency = true}) =>
      send('PUT', path, body: body, includeIdempotency: idempotency);

  /// Helper for DELETE requests.
  Future<ApiResponse> delete(String path) => send('DELETE', path);

  void dispose() {
    _client.close();
  }
}

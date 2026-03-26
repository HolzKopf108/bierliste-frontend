import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/auth_token_response.dart';
import '../models/refresh_token_request.dart';
import 'token_service.dart';

class UnauthorizedException implements Exception {}

class TokenRefreshException implements Exception {
  final String message;
  final int? statusCode;

  TokenRefreshException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

enum TokenRefreshFailureType {
  invalidSession,
  invalidRequest,
  serverError,
  networkError,
  invalidResponse,
}

class TokenRefreshResult {
  final AuthTokenResponse? tokens;
  final TokenRefreshFailureType? failureType;
  final String message;
  final int? statusCode;

  const TokenRefreshResult._({
    this.tokens,
    this.failureType,
    required this.message,
    this.statusCode,
  });

  factory TokenRefreshResult.success(AuthTokenResponse tokens) {
    return TokenRefreshResult._(
      tokens: tokens,
      message: 'Token-Refresh erfolgreich',
      statusCode: 200,
    );
  }

  factory TokenRefreshResult.failure(
    TokenRefreshFailureType failureType,
    String message, {
    int? statusCode,
  }) {
    return TokenRefreshResult._(
      failureType: failureType,
      message: message,
      statusCode: statusCode,
    );
  }

  bool get isSuccess => tokens != null;

  bool get shouldLogout =>
      failureType == TokenRefreshFailureType.invalidSession;

  bool get isTechnicalFailure =>
      failureType == TokenRefreshFailureType.serverError ||
      failureType == TokenRefreshFailureType.networkError;
}

class HttpService {
  static Future<void> Function(String reason)? onUnauthorized;
  static Future<TokenRefreshResult>? _refreshInFlight;

  static Future<http.Response> unauthorizedRequest(
    String url,
    String method, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    headers = Map<String, String>.from(headers ?? const <String, String>{});
    _applyJsonContentType(headers, body);

    final uri = Uri.parse(url);
    late http.Response response;

    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await http.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      } else if (method == 'PUT') {
        response = await http.put(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      } else {
        throw UnsupportedError('HTTP-Methode $method nicht unterstützt');
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<http.Response> authorizedRequest(
    String url,
    String method, {
    Map<String, String>? headers,
    Object? body,
    bool retryOnUnauthorized = true,
  }) async {
    final accessToken = await TokenService.getAccessToken();

    headers = Map<String, String>.from(headers ?? const <String, String>{});
    _applyJsonContentType(headers, body);
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    Uri uri = Uri.parse(url);
    late http.Response response;

    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await http.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      } else if (method == 'PUT') {
        response = await http.put(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      } else if (method == 'DELETE') {
        response = await http.delete(uri, headers: headers);
      } else {
        throw UnsupportedError('HTTP-Methode $method nicht unterstützt');
      }

      if (response.statusCode == 401 && retryOnUnauthorized) {
        final refreshResult = await refreshTokens();
        if (refreshResult.isSuccess) {
          return authorizedRequest(
            url,
            method,
            headers: headers,
            body: body,
            retryOnUnauthorized: false,
          );
        }

        if (refreshResult.shouldLogout) {
          await onUnauthorized?.call(refreshResult.message);
          throw UnauthorizedException();
        }

        throw TokenRefreshException(
          refreshResult.message,
          statusCode: refreshResult.statusCode,
        );
      }

      if (response.statusCode == 401) {
        await onUnauthorized?.call('Sitzung abgelaufen');
        throw UnauthorizedException();
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<TokenRefreshResult> refreshTokens() async {
    if (_refreshInFlight != null) {
      debugPrint(
        'Refresh gestartet: vorhandenen Refresh-Request wiederverwenden',
      );
      return _refreshInFlight!;
    }

    final completer = Completer<TokenRefreshResult>();
    _refreshInFlight = completer.future;

    try {
      final result = await _performRefreshTokens();
      completer.complete(result);
      return result;
    } catch (e, stackTrace) {
      completer.completeError(e, stackTrace);
      rethrow;
    } finally {
      _refreshInFlight = null;
    }
  }

  static Future<TokenRefreshResult> _performRefreshTokens() async {
    final refreshToken = await TokenService.getRefreshToken();
    final sanitizedRefreshToken = refreshToken?.trim();
    if (sanitizedRefreshToken == null || sanitizedRefreshToken.isEmpty) {
      debugPrint('Refresh gestartet: kein gueltiger Refresh-Token vorhanden');
      await TokenService.clearTokens();
      return TokenRefreshResult.failure(
        TokenRefreshFailureType.invalidSession,
        'Keine gueltige Sitzung vorhanden',
      );
    }

    late final http.Response response;
    debugPrint('Refresh gestartet');

    try {
      response = await http.post(
        Uri.parse(
          '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.refresh}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          RefreshTokenRequest(refreshToken: sanitizedRefreshToken).toJson(),
        ),
      );
    } catch (e) {
      debugPrint('Refresh fehlgeschlagen: technischer Fehler beim Request');
      return TokenRefreshResult.failure(
        TokenRefreshFailureType.networkError,
        'Token-Refresh konnte nicht ausgeführt werden',
      );
    }

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic>) {
          throw const FormatException('Ungültige Token-Response');
        }
        final tokens = AuthTokenResponse.fromJson(data);
        await TokenService.saveAuthTokenResponse(tokens);
        debugPrint('Refresh erfolgreich: Tokens ersetzt und gespeichert');
        return TokenRefreshResult.success(tokens);
      } catch (e) {
        debugPrint('Refresh fehlgeschlagen: ungueltige Response');
        return TokenRefreshResult.failure(
          TokenRefreshFailureType.invalidResponse,
          'Token-Refresh lieferte eine ungueltige Antwort',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode == 401) {
      await TokenService.clearTokens();
      debugPrint('Refresh fehlgeschlagen: Statuscode 401, Logout erforderlich');
      return TokenRefreshResult.failure(
        TokenRefreshFailureType.invalidSession,
        'Sitzung abgelaufen. Bitte erneut anmelden.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 400) {
      debugPrint('Refresh fehlgeschlagen: Statuscode 400');
      return TokenRefreshResult.failure(
        TokenRefreshFailureType.invalidRequest,
        'Token-Refresh Request ungueltig (400)',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 500) {
      debugPrint('Refresh fehlgeschlagen: Statuscode ${response.statusCode}');
      return TokenRefreshResult.failure(
        TokenRefreshFailureType.serverError,
        'Token-Refresh fehlgeschlagen (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    debugPrint(
      'Refresh fehlgeschlagen: unerwarteter Statuscode ${response.statusCode}',
    );
    return TokenRefreshResult.failure(
      TokenRefreshFailureType.invalidResponse,
      'Token-Refresh fehlgeschlagen (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  static void _applyJsonContentType(Map<String, String> headers, Object? body) {
    if (body == null) {
      headers.remove('Content-Type');
      return;
    }

    headers['Content-Type'] = 'application/json';
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'token_service.dart';

class UnauthorizedException implements Exception {}

class HttpService {
  static void Function()? onUnauthorized;

  static Future<http.Response> unauthorizedRequest(
    String url,
    String method, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    headers ??= {};
    headers['Content-Type'] = 'application/json';

    final uri = Uri.parse(url);
    late http.Response response;

    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await http.post(uri, headers: headers, body: jsonEncode(body));
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
  }) async {
    final accessToken = await TokenService.getAccessToken();

    headers ??= {};
    headers['Content-Type'] = 'application/json';
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    Uri uri = Uri.parse(url);
    late http.Response response;

    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await http.post(uri, headers: headers, body: jsonEncode(body));
      } else {
        throw UnsupportedError('HTTP-Methode $method nicht unterstützt');
      }

      if (response.statusCode == 401) {
        final success = await refreshTokens();
        if (success) {
          return authorizedRequest(url, method, headers: headers, body: body);
        } else {
          onUnauthorized?.call();
          throw UnauthorizedException();
        }
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<bool> refreshTokens() async {
    final refreshToken = await TokenService.getRefreshToken();
    if (refreshToken == null) return false;

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.refresh}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final accessToken = data['accessToken'];
      final newRefreshToken = data['refreshToken'];
      final userEmail = data['userEmail'] ?? 'unknown';

      await TokenService.saveTokens(accessToken, newRefreshToken, userEmail);
      return true;
    }

    await TokenService.clearTokens();
    return false;
  }
}

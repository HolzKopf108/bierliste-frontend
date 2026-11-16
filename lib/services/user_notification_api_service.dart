import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';

class UserNotificationApiException implements Exception {
  final String message;
  final int? statusCode;

  UserNotificationApiException(this.message, {this.statusCode});
}

class UserNotificationApiService {
  String get _notificationUrl =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.user}/notifications/android';

  Future<void> registerAndroidToken(String token) async {
    await _execute(
      method: 'PUT',
      token: token,
      fallbackMessage:
          'Android-Benachrichtigungen konnten nicht aktiviert werden',
    );
  }

  Future<void> unregisterAndroidToken(String token) async {
    await _execute(
      method: 'DELETE',
      token: token,
      fallbackMessage:
          'Android-Benachrichtigungen konnten nicht deaktiviert werden',
    );
  }

  Future<void> _execute({
    required String method,
    required String token,
    required String fallbackMessage,
  }) async {
    try {
      final response = await HttpService.authorizedRequest(
        _notificationUrl,
        method,
        body: {'token': token},
        retryOnUnauthorized: false,
        triggerUnauthorizedCallback: false,
      );
      _ensureSuccess(response, fallbackMessage);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('_executeUserNotification Token-Refresh-Fehler: ${e.message}');
      throw UserNotificationApiException(e.message, statusCode: e.statusCode);
    } on UserNotificationApiException {
      rethrow;
    } catch (e) {
      debugPrint('_executeUserNotification Fehler: $e');
      throw UserNotificationApiException('Netzwerkfehler');
    }
  }

  void _ensureSuccess(http.Response response, String fallbackMessage) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw UserNotificationApiException(
      _extractErrorMessage(response.body, fallbackMessage),
      statusCode: response.statusCode,
    );
  }

  String _extractErrorMessage(String body, String fallback) {
    if (body.isEmpty) {
      return fallback;
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'] ?? decoded['message'];
        if (error != null && error.toString().trim().isNotEmpty) {
          return error.toString();
        }
      }
    } catch (_) {}

    return fallback;
  }
}

import 'dart:convert';
import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/refresh_token_request.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:flutter/material.dart';

enum DeleteAccountFailureType { unauthorized, network, requestFailed }

class DeleteAccountResult {
  final DeleteAccountFailureType? failureType;
  final String message;
  final int? statusCode;

  const DeleteAccountResult.success()
    : failureType = null,
      message = '',
      statusCode = 200;

  const DeleteAccountResult.failure(
    this.failureType,
    this.message, {
    this.statusCode,
  });

  bool get isSuccess => failureType == null;

  bool get canRetry => failureType != DeleteAccountFailureType.unauthorized;

  bool get shouldLogout => failureType == DeleteAccountFailureType.unauthorized;
}

class UserApiService {
  static Future<DeleteAccountResult> Function()? testDeleteAccount;

  Future<Map<String, dynamic>?> getUser() async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.user}',
        'GET',
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint(
          "getUser failed: ${response.statusCode}, body: ${response.body}",
        );
        return null;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint(e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateUsername({
    required String username,
    required DateTime lastUpdated,
    required bool googleUser,
  }) async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.user}',
        'PUT',
        body: {
          'email': await TokenService.getUserEmail(),
          'username': username,
          'lastUpdated': lastUpdated.toUtc().toIso8601String(),
          'googleUser': googleUser,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint(
          "updateUsername failed: ${response.statusCode}, body: ${response.body}",
        );
        return null;
      }
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      debugPrint(e.toString());
      return null;
    }
  }

  Future<String?> updatePassword({
    required String newPassword,
    required DateTime lastUpdated,
  }) async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.updatePassword}',
        'POST',
        body: {
          'email': await TokenService.getUserEmail(),
          'password': newPassword,
          'lastUpdated': lastUpdated.toUtc().toIso8601String(),
        },
      );

      if (response.statusCode == 200) return null;

      final data = jsonDecode(response.body);
      return data['error'] ?? 'Unbekannter Fehler bei der update password';
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      return 'Netzwerkfehler';
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await TokenService.getRefreshToken();
      if (refreshToken == null) return;

      await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.logout}',
        'POST',
        body: RefreshTokenRequest(refreshToken: refreshToken).toJson(),
      );
    } catch (e) {
      debugPrint('Logout fehlgeschlagen (ignoriert): $e');
      return;
    }
  }

  Future<DeleteAccountResult> deleteAccount() async {
    final deleteOverride = testDeleteAccount;
    if (deleteOverride != null) {
      return deleteOverride();
    }

    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.deleteAccount}',
        'DELETE',
        triggerUnauthorizedCallback: false,
      );

      if (response.statusCode == 200) {
        return const DeleteAccountResult.success();
      }

      if (response.statusCode == 401) {
        return const DeleteAccountResult.failure(
          DeleteAccountFailureType.unauthorized,
          'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.',
          statusCode: 401,
        );
      }

      return DeleteAccountResult.failure(
        DeleteAccountFailureType.requestFailed,
        _deleteAccountFailureMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    } on UnauthorizedException {
      return const DeleteAccountResult.failure(
        DeleteAccountFailureType.unauthorized,
        'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.',
        statusCode: 401,
      );
    } on TokenRefreshException catch (e) {
      if (e.statusCode == 401) {
        return const DeleteAccountResult.failure(
          DeleteAccountFailureType.unauthorized,
          'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.',
          statusCode: 401,
        );
      }

      return DeleteAccountResult.failure(
        DeleteAccountFailureType.requestFailed,
        _deleteAccountFailureMessage(e.statusCode),
        statusCode: e.statusCode,
      );
    } catch (_) {
      return const DeleteAccountResult.failure(
        DeleteAccountFailureType.network,
        'Keine Verbindung. Bitte versuche es erneut.',
      );
    }
  }

  String _deleteAccountFailureMessage(int? statusCode) {
    if (statusCode != null && statusCode >= 500) {
      return 'Konto konnte gerade nicht gelöscht werden. Bitte versuche es erneut.';
    }

    return 'Konto konnte nicht gelöscht werden. Bitte versuche es erneut.';
  }
}

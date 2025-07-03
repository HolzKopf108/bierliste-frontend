

import 'dart:convert';
import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:flutter/material.dart';

class UserApiService {
  Future<Map<String, dynamic>?> getUser() async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.user}',
        'GET',
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint("getUser failed: ${response.statusCode}, body: ${response.body}");
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
        debugPrint("updateUsername failed: ${response.statusCode}, body: ${response.body}");
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
        body: {'refreshToken': refreshToken},
      );
    } catch (e) {
      debugPrint('Logout fehlgeschlagen (ignoriert): $e');
      return;
    }
  }
}
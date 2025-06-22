

import 'dart:convert';
import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:flutter/material.dart';

class UserApiService {
  Future<String?> resetPasswordSet({required String newPassword}) async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.resetPasswordSet}',
        'POST',
        body: {
          'newPassword': newPassword,
        },
      );

      if (response.statusCode == 200) return null;

      final data = jsonDecode(response.body);
      return data['error'] ?? 'Unbekannter Fehler bei der reset password';
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
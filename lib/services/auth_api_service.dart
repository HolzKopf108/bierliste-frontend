import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import 'http_service.dart';
import '../providers/auth_provider.dart';

class AuthApiService {
  Future<String?> registerUser({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      final response = await HttpService.unauthorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.register}',
        'POST',
        body: {
          'email': email,
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) return null;

      final data = jsonDecode(response.body);
      return data['error'] ?? 'Unbekannter Fehler bei der Registrierung';
    } catch (e) {
      debugPrint('Fehler bei Registrierung: $e');
      return 'Netzwerkfehler';
    }
  }

  Future<String?> loginUser({
    required String email,
    required String password,
    required AuthProvider authProvider,
  }) async {
    try {
      final response = await HttpService.unauthorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.login}',
        'POST',
        body: {
          'email': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];
        final userEmail = data['userEmail'] ?? 'unknown';

        await authProvider.login(accessToken, refreshToken, userEmail);
        return null;
      } else {
        final body = jsonDecode(response.body);
        return body['error'] ?? 'Login fehlgeschlagen';
      }
    } catch (e) {
      debugPrint('Login Fehler: $e');
      return 'Verbindung fehlgeschlagen';
    }
  }

  Future<String?> loginGoogle(String idToken, AuthProvider authProvider,) async {
    try {
      final response = await HttpService.unauthorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.google}',
        'POST',
        body: {'idToken': idToken},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];
        final userEmail = data['userEmail'] ?? 'unknown';

        await authProvider.login(accessToken, refreshToken, userEmail);
        return null;
      } else {
        final body = jsonDecode(response.body);
        return body['error'] ?? 'Login mit Google fehlgeschlagen';
      }
    } catch (e) {
      debugPrint('Google Login Fehler: $e');
      return 'Verbindung fehlgeschlagen';
    }
  }

  Future<String?> verifyEmail({
    required String email,
    required String code,
    required AuthProvider authProvider,
  }) async {
    try {
      final response = await HttpService.unauthorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.verify}',
        'POST',
        body: {
          'email': email,
          'code': code,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['accessToken'];
        final refreshToken = data['refreshToken'];
        final userEmail = data['userEmail'] ?? 'unknown';

        await authProvider.login(accessToken, refreshToken, userEmail);
        return null;
      } else if (response.statusCode == 403) {
        final body = jsonDecode(response.body);
        final error = body['error'] ?? '';
        if (error.contains('nicht verifiziert')) {
          await resendVerificationCode(email: email);
          return 'E-Mail nicht verifiziert. Neuer Code gesendet.';
        } else {
          return 'Unbekannter Fehler bei Verifizierung';
        }
      } else {
        final body = jsonDecode(response.body);
        return body['error'] ?? 'Verifizierung fehlgeschlagen';
      }
    } catch (e) {
      debugPrint('Verifizierungsfehler: $e');
      return 'Verbindung fehlgeschlagen';
    }
  }

  Future<String?> resendVerificationCode({required String email}) async {
    try {
      final response = await HttpService.unauthorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.resendVerify}',
        'POST',
        body: {'email': email},
      );

      if (response.statusCode == 200) return null;

      final body = jsonDecode(response.body);
      return body['error'] ?? 'Fehler beim erneuten Senden';
    } catch (e) {
      debugPrint('Fehler bei resend: $e');
      return 'Verbindungsfehler';
    }
  }

  Future<String?> resetPassword({required String email}) async {
    try {
      final response = await HttpService.unauthorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.resetPassword}',
        'POST',
        body: {'email': email},
      );

      if (response.statusCode == 200) return null;

      final body = jsonDecode(response.body);
      return body['error'] ?? 'Unbekannter Fehler beim Zurücksetzen';
    } catch (e) {
      debugPrint('Fehler bei resetPassword: $e');
      return 'Verbindungsfehler';
    }
  }
}

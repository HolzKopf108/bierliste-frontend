import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/counter.dart';

class ApiService {
  Future<Counter?> fetchCounter() async {
    try {
      final response = await http.get(Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.counter}'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Counter.fromJson(data);
      }
    } catch (e) {
      debugPrint('Fehler beim Laden: $e');
    }
    return null;
  }

  Future<bool> updateCounter(Counter counter) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.counter}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(counter.toJson()),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Fehler beim Senden: $e');
      return false;
    }
  }

  Future<String?> registerUser({
    required String email,
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.register}');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        return null;
      } else {
        final data = jsonDecode(response.body);
        return data['error'] ?? 'Unbekannter Fehler bei register';
      }
    } catch (e) {
      debugPrint('Fehler bei Registrierung: $e');
      return 'Netzwerkfehler';
    }
  }

  Future<String?> loginUser({
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.login}');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('accessToken', data['accessToken']);
        await prefs.setString('refreshToken', data['refreshToken']);
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

  Future<String?> verifyEmail({
    required String email,
    required String code,
  }) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.verify}');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('accessToken', data['accessToken']);
        await prefs.setString('refreshToken', data['refreshToken']);
        return null;
      } else if (response.statusCode == 403) {
        final body = jsonDecode(response.body);
        final error = body['error'] ?? '';
        if (error.contains('nicht verifiziert')) {
          await resendVerificationCode(email: email);
          return 'E-Mail nicht verifiziert. Neuer Code gesendet.';
        } else {
          return 'Unbekannter Fehler bei verify';
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
    final url = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.resend}');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) return null;

      final body = jsonDecode(response.body);
      return body['error'] ?? 'Fehler beim erneuten Senden';
    } catch (e) {
      debugPrint('Fehler bei resend: $e');
      return 'Verbindungsfehler';
    }
  }
}

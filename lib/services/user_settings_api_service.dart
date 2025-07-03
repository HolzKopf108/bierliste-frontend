import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'package:bierliste/services/http_service.dart';

class UserSettingsApiService {
  Future<Map<String, dynamic>?> getUserSettings() async {
     final response = await HttpService.authorizedRequest(
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.userSettings}',
      'GET',
     );
     
     if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      debugPrint("getUserSettigs failed: ${response.statusCode}, body: ${response.body}");
      return null;
    }
  }

  Future<bool> verifyPassword(String password) async {
    final response = await HttpService.authorizedRequest(
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.userVerifyPassword}',
      'POST',
      body: {'password': password},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['valid'] == true;
    }

    return false;
  }

  Future<http.Response> updateSettings(String theme, bool autoSyncEnabled, DateTime lastUpdated) async {
    final response = await HttpService.authorizedRequest(
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.userSettings}',
      'PUT',
      body: {
        'theme': theme,
        'autoSyncEnabled': autoSyncEnabled,
        'lastUpdated': lastUpdated.toUtc().toIso8601String(),
      },
    );

    return response;
  }
}

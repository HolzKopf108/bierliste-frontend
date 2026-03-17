import 'dart:async';
import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/group_settings.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';

class GroupSettingsApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupSettingsApiException(this.message, {this.statusCode});
}

class GroupSettingsApiService {
  static const _requestTimeout = Duration(seconds: 5);

  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<GroupSettings> fetchGroupSettings(
    int groupId, {
    Duration timeout = _requestTimeout,
  }) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/settings',
        'GET',
      ).timeout(timeout);
      _ensureSuccess(
        response,
        'Gruppeneinstellungen konnten nicht geladen werden',
      );

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupSettingsApiException('Ungültige Serverantwort');
      }

      return GroupSettings.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('fetchGroupSettings Token-Refresh-Fehler: ${e.message}');
      throw GroupSettingsApiException(e.message, statusCode: e.statusCode);
    } on FormatException catch (e) {
      debugPrint('fetchGroupSettings Parse-Fehler: $e');
      throw GroupSettingsApiException('Ungültige Serverantwort');
    } on GroupSettingsApiException {
      rethrow;
    } catch (e) {
      debugPrint('fetchGroupSettings Fehler: $e');
      throw GroupSettingsApiException('Netzwerkfehler');
    }
  }

  Future<GroupSettings> updateGroupSettings(
    int groupId,
    GroupSettings payload, {
    Duration timeout = _requestTimeout,
  }) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/settings',
        'PUT',
        body: payload.toJson(),
      ).timeout(timeout);
      _ensureSuccess(
        response,
        'Gruppeneinstellungen konnten nicht aktualisiert werden',
      );

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupSettingsApiException('Ungültige Serverantwort');
      }

      return GroupSettings.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('updateGroupSettings Token-Refresh-Fehler: ${e.message}');
      throw GroupSettingsApiException(e.message, statusCode: e.statusCode);
    } on FormatException catch (e) {
      debugPrint('updateGroupSettings Parse-Fehler: $e');
      throw GroupSettingsApiException('Ungültige Serverantwort');
    } on GroupSettingsApiException {
      rethrow;
    } catch (e) {
      debugPrint('updateGroupSettings Fehler: $e');
      throw GroupSettingsApiException('Netzwerkfehler');
    }
  }

  dynamic _decode(String body) {
    if (body.isEmpty) {
      return null;
    }
    return jsonDecode(body);
  }

  void _ensureSuccess(http.Response response, String fallbackMessage) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw GroupSettingsApiException(
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

        final validationMessages = decoded.values
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .map((value) => value.toString())
            .toList();
        if (validationMessages.isNotEmpty) {
          return validationMessages.join('\n');
        }
      }
    } catch (_) {}

    return fallback;
  }
}

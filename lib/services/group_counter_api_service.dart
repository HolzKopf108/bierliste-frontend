import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/group_counter.dart';
import 'package:bierliste/models/increment_request.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';
import 'offline_strich_service.dart';

class GroupCounterApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupCounterApiException(this.message, {this.statusCode});
}

class GroupCounterApiService {
  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<GroupCounter> fetchMyGroupCounter(int groupId) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/me/counter',
        'GET',
      );
      _ensureSuccess(response, 'Gruppen-Counter konnte nicht geladen werden');

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupCounterApiException('Ungültige Serverantwort');
      }

      return GroupCounter.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('fetchMyGroupCounter Token-Refresh-Fehler: ${e.message}');
      throw GroupCounterApiException(e.message);
    } on GroupCounterApiException {
      rethrow;
    } catch (e) {
      debugPrint('fetchMyGroupCounter Fehler: $e');
      throw GroupCounterApiException('Netzwerkfehler');
    }
  }

  Future<GroupCounter> incrementMyGroupCounter(int groupId, int amount) async {
    if (amount < 1) {
      throw GroupCounterApiException('Ungültiger Inkrement-Wert');
    }

    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/me/counter/increment',
        'POST',
        body: IncrementRequest(amount: amount).toJson(),
      );
      _ensureSuccess(
        response,
        'Gruppen-Counter konnte nicht aktualisiert werden',
      );

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupCounterApiException('Ungültige Serverantwort');
      }

      return GroupCounter.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('incrementMyGroupCounter Token-Refresh-Fehler: ${e.message}');
      throw GroupCounterApiException(e.message);
    } on GroupCounterApiException {
      rethrow;
    } catch (e) {
      debugPrint('incrementMyGroupCounter Fehler: $e');
      throw GroupCounterApiException('Netzwerkfehler');
    }
  }

  Future<bool> syncPendingCounterOperations(
    String userEmail, {
    int? groupId,
  }) async {
    return OfflineStrichService.syncPendingOperations(
      userEmail,
      groupId: groupId,
    );
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
    throw GroupCounterApiException(
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

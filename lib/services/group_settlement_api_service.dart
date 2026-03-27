import 'dart:async';
import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/group_settlement_result.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';

class GroupSettlementApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupSettlementApiException(this.message, {this.statusCode});
}

class GroupSettlementApiService {
  static const _requestTimeout = Duration(seconds: 5);

  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<GroupSettlementResult> settleMoney(
    int groupId,
    int targetUserId,
    double amount, {
    Duration timeout = _requestTimeout,
  }) async {
    if (amount <= 0) {
      throw GroupSettlementApiException('Ungültiger Betrag');
    }

    return _createSettlement(
      groupId,
      targetUserId,
      endpoint: 'money',
      amount: amount,
      timeout: timeout,
      fallbackMessage: 'Geld konnte nicht eingezahlt werden',
    );
  }

  Future<GroupSettlementResult> settleStriche(
    int groupId,
    int targetUserId,
    int amount, {
    Duration timeout = _requestTimeout,
  }) async {
    if (amount <= 0) {
      throw GroupSettlementApiException('Ungültige Anzahl');
    }

    return _createSettlement(
      groupId,
      targetUserId,
      endpoint: 'striche',
      amount: amount,
      timeout: timeout,
      fallbackMessage: 'Striche konnten nicht verrechnet werden',
    );
  }

  Future<GroupSettlementResult> _createSettlement(
    int groupId,
    int targetUserId, {
    required String endpoint,
    required num amount,
    required Duration timeout,
    required String fallbackMessage,
  }) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/members/$targetUserId/settlements/$endpoint',
        'POST',
        body: {'amount': amount},
      ).timeout(timeout);
      _ensureSuccess(response, fallbackMessage);

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupSettlementApiException('Ungültige Serverantwort');
      }

      return GroupSettlementResult.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('_createSettlement Token-Refresh-Fehler: ${e.message}');
      throw GroupSettlementApiException(e.message, statusCode: e.statusCode);
    } on FormatException catch (e) {
      debugPrint('_createSettlement Parse-Fehler: $e');
      throw GroupSettlementApiException('Ungültige Serverantwort');
    } on GroupSettlementApiException {
      rethrow;
    } catch (e) {
      debugPrint('_createSettlement Fehler: $e');
      throw GroupSettlementApiException('Netzwerkfehler');
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

    throw GroupSettlementApiException(
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

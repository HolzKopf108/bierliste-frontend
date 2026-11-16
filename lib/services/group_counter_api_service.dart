import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/counter_increment_result.dart';
import 'package:bierliste/models/counter_undo_result.dart';
import 'package:bierliste/models/group_counter.dart';
import 'package:bierliste/models/increment_request.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';
import 'offline_strich_service.dart';
import 'token_service.dart';
import '../models/pending_sync_operation.dart';

class GroupCounterApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupCounterApiException(this.message, {this.statusCode});
}

class GroupCounterApiService {
  static Future<List<Map<String, dynamic>>> Function(
    List<PendingSyncOperation>,
  )?
  testSyncEvents;

  Future<List<Map<String, dynamic>>> syncEvents(
    List<PendingSyncOperation> operations,
  ) async {
    final override = testSyncEvents;
    late List<Map<String, dynamic>> results;
    if (override != null) {
      results = await override(operations);
    } else {
      final userEmail = await TokenService.getUserEmail();
      if (userEmail == null ||
          operations.any((operation) => operation.userEmail != userEmail)) {
        throw UnauthorizedException();
      }
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/sync/events',
        'POST',
        body: {
          'events': operations
              .map((operation) => operation.toClientEvent())
              .toList(),
        },
      ).timeout(const Duration(seconds: 20));
      _ensureSuccess(response, 'Synchronisierung fehlgeschlagen');
      final data = _decode(response.body);
      if (data is! Map || data['results'] is! List) {
        throw GroupCounterApiException('Ungueltige Sync-Antwort');
      }
      results = (data['results'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList();
    }
    final expectedIds = operations
        .map((operation) => operation.clientEventId)
        .toSet();
    final ids = results.map((result) => result['clientEventId']).toSet();
    if (results.length != operations.length ||
        ids.length != results.length ||
        !ids.containsAll(expectedIds)) {
      throw GroupCounterApiException('Unvollstaendige Sync-Antwort');
    }
    for (final result in results) {
      if (!const [
        'applied',
        'duplicate',
        'failed',
      ].contains(result['status'])) {
        throw GroupCounterApiException('Unbekannter Sync-Status');
      }
      if (result['status'] != 'failed') {
        CounterIncrementResult.fromJson(
          Map<String, dynamic>.from(result['serverStateDelta'] as Map),
        );
      }
    }
    return results;
  }

  static Future<GroupCounter> Function(int groupId)? testFetchMyGroupCounter;
  static Future<CounterIncrementResult> Function(int groupId, int amount)?
  testIncrementMyGroupCounter;
  static Future<CounterIncrementResult> Function(
    int groupId,
    int targetUserId,
    int amount,
  )?
  testIncrementGroupMemberCounter;
  static Future<CounterUndoResult> Function(
    int groupId,
    int incrementRequestId,
  )?
  testUndoCounterIncrement;

  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<GroupCounter> fetchMyGroupCounter(int groupId) async {
    final fetchOverride = testFetchMyGroupCounter;
    if (fetchOverride != null) {
      return fetchOverride(groupId);
    }

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

  Future<CounterIncrementResult> incrementMyGroupCounter(
    int groupId,
    int amount,
  ) async {
    final incrementOverride = testIncrementMyGroupCounter;
    if (incrementOverride != null) {
      return incrementOverride(groupId, amount);
    }

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

      return CounterIncrementResult.fromJson(data);
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

  Future<CounterIncrementResult> incrementGroupMemberCounter(
    int groupId,
    int targetUserId,
    int amount,
  ) async {
    final incrementOverride = testIncrementGroupMemberCounter;
    if (incrementOverride != null) {
      return incrementOverride(groupId, targetUserId, amount);
    }

    if (amount < 1) {
      throw GroupCounterApiException('Ungültiger Inkrement-Wert');
    }

    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/members/$targetUserId/counter/increment',
        'POST',
        body: IncrementRequest(amount: amount).toJson(),
      );
      _ensureSuccess(
        response,
        'Counter des Mitglieds konnte nicht aktualisiert werden',
      );

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupCounterApiException('Ungültige Serverantwort');
      }

      return CounterIncrementResult.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint(
        'incrementGroupMemberCounter Token-Refresh-Fehler: ${e.message}',
      );
      throw GroupCounterApiException(e.message);
    } on GroupCounterApiException {
      rethrow;
    } catch (e) {
      debugPrint('incrementGroupMemberCounter Fehler: $e');
      throw GroupCounterApiException('Netzwerkfehler');
    }
  }

  Future<CounterUndoResult> undoCounterIncrement(
    int groupId,
    int incrementRequestId,
  ) async {
    final undoOverride = testUndoCounterIncrement;
    if (undoOverride != null) {
      return undoOverride(groupId, incrementRequestId);
    }

    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/counter/increments/$incrementRequestId/undo',
        'POST',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'undoCounterIncrement HTTP-Fehler: '
          'groupId=$groupId incrementRequestId=$incrementRequestId '
          'status=${response.statusCode} body=${response.body}',
        );
      }
      _ensureSuccess(response, 'Strich konnte nicht rückgängig gemacht werden');

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupCounterApiException('Ungültige Serverantwort');
      }

      return CounterUndoResult.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('undoCounterIncrement Token-Refresh-Fehler: ${e.message}');
      throw GroupCounterApiException(e.message, statusCode: e.statusCode);
    } on GroupCounterApiException {
      rethrow;
    } catch (e) {
      debugPrint('undoCounterIncrement Fehler: $e');
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

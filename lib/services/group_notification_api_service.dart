import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/group_member_notification.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';

class GroupNotificationApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupNotificationApiException(this.message, {this.statusCode});
}

class GroupNotificationApiService {
  static Future<List<GroupMemberNotification>> Function(int groupId)?
  testFetchMyNotifications;
  static Future<GroupMemberNotification> Function(
    int groupId,
    int targetUserId,
    String message,
  )?
  testSendNotification;
  static Future<GroupMemberNotification> Function(
    int groupId,
    int notificationId,
  )?
  testConfirmNotification;

  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<List<GroupMemberNotification>> fetchMyNotifications(
    int groupId,
  ) async {
    final fetchOverride = testFetchMyNotifications;
    if (fetchOverride != null) {
      return fetchOverride(groupId);
    }

    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/notifications/me',
        'GET',
      );
      _ensureSuccess(
        response,
        'Benachrichtigungen konnten nicht geladen werden',
      );

      final data = _decode(response.body);
      if (data == null) {
        return [];
      }

      if (data is! List) {
        throw GroupNotificationApiException('Ungültige Serverantwort');
      }

      return data.map<GroupMemberNotification>((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Ungültiger Benachrichtigungs-Eintrag');
        }
        return GroupMemberNotification.fromJson(entry);
      }).toList();
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('fetchMyNotifications Token-Refresh-Fehler: ${e.message}');
      throw GroupNotificationApiException(e.message);
    } on FormatException catch (e) {
      debugPrint('fetchMyNotifications Parse-Fehler: $e');
      throw GroupNotificationApiException('Ungültige Serverantwort');
    } on GroupNotificationApiException {
      rethrow;
    } catch (e) {
      debugPrint('fetchMyNotifications Fehler: $e');
      throw GroupNotificationApiException('Netzwerkfehler');
    }
  }

  Future<GroupMemberNotification> sendNotification(
    int groupId,
    int targetUserId,
    String message,
  ) async {
    final sendOverride = testSendNotification;
    if (sendOverride != null) {
      return sendOverride(groupId, targetUserId, message);
    }

    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/members/$targetUserId/notifications',
        'POST',
        body: {'message': message},
      );
      _ensureSuccess(response, 'Benachrichtigung konnte nicht gesendet werden');

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupNotificationApiException('Ungültige Serverantwort');
      }

      return GroupMemberNotification.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('sendNotification Token-Refresh-Fehler: ${e.message}');
      throw GroupNotificationApiException(e.message);
    } on FormatException catch (e) {
      debugPrint('sendNotification Parse-Fehler: $e');
      throw GroupNotificationApiException('Ungültige Serverantwort');
    } on GroupNotificationApiException {
      rethrow;
    } catch (e) {
      debugPrint('sendNotification Fehler: $e');
      throw GroupNotificationApiException('Netzwerkfehler');
    }
  }

  Future<GroupMemberNotification> confirmNotification(
    int groupId,
    int notificationId,
  ) async {
    final confirmOverride = testConfirmNotification;
    if (confirmOverride != null) {
      return confirmOverride(groupId, notificationId);
    }

    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/notifications/$notificationId/confirm',
        'POST',
      );
      _ensureSuccess(
        response,
        'Benachrichtigung konnte nicht bestätigt werden',
      );

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupNotificationApiException('Ungültige Serverantwort');
      }

      return GroupMemberNotification.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('confirmNotification Token-Refresh-Fehler: ${e.message}');
      throw GroupNotificationApiException(e.message);
    } on FormatException catch (e) {
      debugPrint('confirmNotification Parse-Fehler: $e');
      throw GroupNotificationApiException('Ungültige Serverantwort');
    } on GroupNotificationApiException {
      rethrow;
    } catch (e) {
      debugPrint('confirmNotification Fehler: $e');
      throw GroupNotificationApiException('Netzwerkfehler');
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
    throw GroupNotificationApiException(
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

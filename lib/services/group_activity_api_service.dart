import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/group_activity.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';

class GroupActivityApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupActivityApiException(this.message, {this.statusCode});
}

class GroupActivityApiService {
  static const int defaultLimit = 50;
  static const int minLimit = 1;
  static const int maxLimit = 100;

  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<GroupActivitiesResponse> fetchGroupActivities(
    int groupId, {
    String? cursor,
    int? limit,
  }) async {
    final effectiveLimit = _sanitizeLimit(limit);
    final queryParameters = <String, String>{
      'limit': effectiveLimit.toString(),
    };
    final sanitizedCursor = cursor?.trim();
    if (sanitizedCursor != null && sanitizedCursor.isNotEmpty) {
      queryParameters['cursor'] = sanitizedCursor;
    }

    final uri = Uri.parse(
      '$_groupsBase/$groupId/activities',
    ).replace(queryParameters: queryParameters);

    try {
      final response = await HttpService.authorizedRequest(
        uri.toString(),
        'GET',
      );
      _ensureSuccess(response, 'Verlauf konnte nicht geladen werden');

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupActivityApiException('Ungueltige Serverantwort');
      }

      return GroupActivitiesResponse.fromJson(
        data,
        requestedLimit: effectiveLimit,
      );
    } on UnauthorizedException {
      rethrow;
    } on TokenRefreshException catch (e) {
      debugPrint('fetchGroupActivities Token-Refresh-Fehler: ${e.message}');
      throw GroupActivityApiException(e.message, statusCode: e.statusCode);
    } on FormatException catch (e) {
      debugPrint('fetchGroupActivities Parse-Fehler: $e');
      throw GroupActivityApiException('Ungueltige Serverantwort');
    } on GroupActivityApiException {
      rethrow;
    } catch (e) {
      debugPrint('fetchGroupActivities Fehler: $e');
      throw GroupActivityApiException('Netzwerkfehler');
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

    throw GroupActivityApiException(
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

  int _sanitizeLimit(int? limit) {
    final parsedLimit = limit ?? defaultLimit;
    if (parsedLimit < minLimit) {
      return minLimit;
    }

    if (parsedLimit > maxLimit) {
      return maxLimit;
    }

    return parsedLimit;
  }
}

import 'dart:convert';

import 'package:bierliste/config/app_config.dart';
import 'package:bierliste/models/group.dart';
import 'package:bierliste/models/group_member.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_service.dart';

class GroupApiException implements Exception {
  final String message;
  final int? statusCode;

  GroupApiException(this.message, {this.statusCode});
}

class GroupApiService {
  String get _groupsBase =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}/groups';

  Future<List<Group>> listGroups() async {
    try {
      final response = await HttpService.authorizedRequest(_groupsBase, 'GET');
      _ensureSuccess(response, 'Gruppen konnten nicht geladen werden');

      final data = _decode(response.body);
      if (data == null) {
        return [];
      }

      if (data is! List) {
        throw GroupApiException('Ungültige Serverantwort');
      }

      return data
          .whereType<Map<String, dynamic>>()
          .map(Group.fromJson)
          .toList();
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException {
      rethrow;
    } catch (e) {
      debugPrint('listGroups Fehler: $e');
      throw GroupApiException('Netzwerkfehler');
    }
  }

  Future<Group> createGroup(String name) async {
    try {
      final response = await HttpService.authorizedRequest(
        _groupsBase,
        'POST',
        body: {'name': name},
      );
      _ensureSuccess(response, 'Gruppe konnte nicht erstellt werden');

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupApiException('Ungültige Serverantwort');
      }

      return Group.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException {
      rethrow;
    } catch (e) {
      debugPrint('createGroup Fehler: $e');
      throw GroupApiException('Netzwerkfehler');
    }
  }

  Future<Group> getGroup(int groupId) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId',
        'GET',
      );
      _ensureSuccess(response, 'Gruppe konnte nicht geladen werden');

      final data = _decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw GroupApiException('Ungültige Serverantwort');
      }

      return Group.fromJson(data);
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException {
      rethrow;
    } catch (e) {
      debugPrint('getGroup Fehler: $e');
      throw GroupApiException('Netzwerkfehler');
    }
  }

  Future<List<GroupMember>> listMembers(int groupId) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/members',
        'GET',
      );
      _ensureSuccess(response, 'Mitglieder konnten nicht geladen werden');

      final data = _decode(response.body);
      if (data == null) {
        return [];
      }

      if (data is! List) {
        throw GroupApiException('Ungültige Serverantwort');
      }

      return data
          .whereType<Map<String, dynamic>>()
          .map(GroupMember.fromJson)
          .toList();
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException {
      rethrow;
    } catch (e) {
      debugPrint('listMembers Fehler: $e');
      throw GroupApiException('Netzwerkfehler');
    }
  }

  Future<void> joinGroup(int groupId) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/join',
        'POST',
      );
      _ensureSuccess(response, 'Beitritt zur Gruppe fehlgeschlagen');
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException {
      rethrow;
    } catch (e) {
      debugPrint('joinGroup Fehler: $e');
      throw GroupApiException('Netzwerkfehler');
    }
  }

  Future<void> leaveGroup(int groupId) async {
    try {
      final response = await HttpService.authorizedRequest(
        '$_groupsBase/$groupId/leave',
        'POST',
      );
      _ensureSuccess(response, 'Gruppe konnte nicht verlassen werden');
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException {
      rethrow;
    } catch (e) {
      debugPrint('leaveGroup Fehler: $e');
      throw GroupApiException('Netzwerkfehler');
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
    throw GroupApiException(
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

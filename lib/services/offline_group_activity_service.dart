import 'dart:async';

import 'package:bierliste/models/group_activity.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:hive/hive.dart';

import 'group_activity_api_service.dart';

class OfflineGroupActivityService {
  static const _boxName = 'group_activity_cache';
  static const _requestTimeout = Duration(seconds: 5);

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }

    return Hive.openBox(_boxName);
  }

  static Future<void> saveGroupActivities(
    String userEmail,
    int groupId,
    GroupActivitiesResponse response,
  ) async {
    final box = await _openBox();
    await box.put(
      _groupActivitiesKey(userEmail, groupId),
      GroupActivitiesResponse(
        items: response.items.take(response.limit).toList(),
        nextCursor: response.nextCursor,
        limit: response.limit,
      ).toJson(),
    );
  }

  static Future<GroupActivitiesResponse?> getGroupActivities(
    String userEmail,
    int groupId,
  ) async {
    final box = await _openBox();
    final rawValue = box.get(_groupActivitiesKey(userEmail, groupId));
    if (rawValue is! Map) {
      return null;
    }

    try {
      return GroupActivitiesResponse.fromCacheJson(
        Map<String, dynamic>.from(rawValue),
      );
    } catch (_) {
      await box.delete(_groupActivitiesKey(userEmail, groupId));
      return null;
    }
  }

  static Future<GroupActivitiesResponse> refreshGroupActivities(
    String userEmail,
    int groupId, {
    int limit = GroupActivityApiService.defaultLimit,
    Duration timeout = _requestTimeout,
  }) async {
    final response = await GroupActivityApiService()
        .fetchGroupActivities(groupId, limit: limit)
        .timeout(timeout);
    await saveGroupActivities(userEmail, groupId, response);
    return response;
  }

  static Future<bool> syncGroupActivitiesInBackground(
    String userEmail,
    Iterable<int> groupIds, {
    int limit = GroupActivityApiService.defaultLimit,
    Duration timeout = _requestTimeout,
  }) async {
    if (!await ConnectivityService.isOnline()) {
      return false;
    }

    try {
      for (final groupId in groupIds) {
        try {
          await refreshGroupActivities(
            userEmail,
            groupId,
            limit: limit,
            timeout: timeout,
          );
        } on UnauthorizedException {
          rethrow;
        } catch (_) {}
      }

      return true;
    } on UnauthorizedException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  static String _groupActivitiesKey(String userEmail, int groupId) {
    return 'group_activity_cache_${userEmail}_$groupId';
  }
}

import 'dart:async';

import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:hive/hive.dart';

class GroupMemberCacheService {
  static const _boxName = 'group_member_cache';
  static const _requestTimeout = Duration(seconds: 5);

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return await Hive.openBox(_boxName);
    }
  }

  static Future<void> saveGroupMembers(
    String userEmail,
    int groupId,
    List<GroupMember> members,
  ) async {
    final box = await _openBox();
    await box.put(
      _groupMembersKey(userEmail, groupId),
      members.map((member) => member.toJson()).toList(),
    );
  }

  static Future<List<GroupMember>?> getGroupMembers(
    String userEmail,
    int groupId,
  ) async {
    final box = await _openBox();
    final rawList = box.get(_groupMembersKey(userEmail, groupId));
    if (rawList is! List) {
      return null;
    }

    try {
      return rawList.map<GroupMember>((entry) {
        if (entry is! Map) {
          throw const FormatException('Ungültiger Cache-Eintrag');
        }

        return GroupMember.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
    } catch (_) {
      await box.delete(_groupMembersKey(userEmail, groupId));
      return null;
    }
  }

  static Future<List<GroupMember>> refreshGroupMembers(
    String userEmail,
    int groupId, {
    Duration timeout = _requestTimeout,
  }) async {
    final members = await GroupApiService()
        .fetchGroupMembers(groupId)
        .timeout(timeout);
    await saveGroupMembers(userEmail, groupId, members);
    return members;
  }

  static Future<bool> syncGroupMembersInBackground(
    String userEmail,
    Iterable<int> groupIds, {
    Duration timeout = _requestTimeout,
  }) async {
    if (!await ConnectivityService.isOnline()) {
      return false;
    }

    try {
      for (final groupId in groupIds) {
        try {
          await refreshGroupMembers(userEmail, groupId, timeout: timeout);
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

  static String _groupMembersKey(String userEmail, int groupId) {
    return 'group_members_cache_${userEmail}_$groupId';
  }
}

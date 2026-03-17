import 'dart:async';

import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/services/offline_group_users_service.dart';

class GroupMemberCacheService {
  static Future<void> saveGroupMembers(
    String userEmail,
    int groupId,
    List<GroupMember> members,
  ) async {
    await OfflineGroupUsersService.saveGroupMembers(
      userEmail,
      groupId,
      members,
    );
  }

  static Future<List<GroupMember>?> getGroupMembers(
    String userEmail,
    int groupId,
  ) async {
    return OfflineGroupUsersService.getGroupMembers(userEmail, groupId);
  }

  static Future<List<GroupMember>> refreshGroupMembers(
    String userEmail,
    int groupId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return OfflineGroupUsersService.refreshGroupMembers(
      userEmail,
      groupId,
      timeout: timeout,
    );
  }

  static Future<bool> syncGroupMembersInBackground(
    String userEmail,
    Iterable<int> groupIds, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return OfflineGroupUsersService.syncGroupMembersInBackground(
      userEmail,
      groupIds,
      timeout: timeout,
    );
  }
}

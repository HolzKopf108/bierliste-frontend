import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:hive/hive.dart';

class GroupRoleCacheService {
  static const _boxName = 'group_role_cache';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> saveGroupRole(
    String userEmail,
    int groupId,
    GroupMemberRole role,
  ) async {
    final box = await _openBox();
    await box.put(_groupRoleKey(userEmail, groupId), role.jsonValue);
  }

  static Future<GroupMemberRole?> getGroupRole(
    String userEmail,
    int groupId,
  ) async {
    final box = await _openBox();
    final rawRole = box.get(_groupRoleKey(userEmail, groupId));
    if (rawRole == null) {
      return null;
    }

    final role = GroupMemberRole.fromJsonValue(rawRole);
    if (role == GroupMemberRole.unknown) {
      await box.delete(_groupRoleKey(userEmail, groupId));
      return null;
    }

    return role;
  }

  static Future<GroupMemberRole> refreshGroupRole(
    String userEmail,
    int groupId,
  ) async {
    final role = await GroupApiService().fetchOwnGroupRole(groupId);
    await saveGroupRole(userEmail, groupId, role);
    return role;
  }

  static Future<void> clearForUser(String userEmail) async {
    final box = await _openBox();
    final matchingKeys = box.keys
        .where(
          (key) => key.toString().startsWith('group_role_cache_${userEmail}_'),
        )
        .toList();

    await box.deleteAll(matchingKeys);
  }

  static String _groupRoleKey(String userEmail, int groupId) {
    return 'group_role_cache_${userEmail}_$groupId';
  }
}

import 'package:bierliste/models/group.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:hive/hive.dart';

class OfflineGroupSettingsService {
  static const _boxName = 'group_settings_cache';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> saveGroup(String userEmail, Group group) async {
    final box = await _openBox();
    await box.put(_groupSettingsKey(userEmail, group.id), group.toJson());
  }

  static Future<Group?> getGroup(String userEmail, int groupId) async {
    final box = await _openBox();
    final rawGroup = box.get(_groupSettingsKey(userEmail, groupId));
    if (rawGroup is! Map) {
      return null;
    }

    try {
      return Group.fromJson(Map<String, dynamic>.from(rawGroup));
    } catch (_) {
      await box.delete(_groupSettingsKey(userEmail, groupId));
      return null;
    }
  }

  static Future<Group> refreshGroup(String userEmail, int groupId) async {
    final group = await GroupApiService().getGroup(groupId);
    await saveGroup(userEmail, group);
    return group;
  }

  static Future<bool> syncPendingOperations(String userEmail) async {
    return true;
  }

  static String _groupSettingsKey(String userEmail, int groupId) {
    return 'group_settings_cache_${userEmail}_$groupId';
  }
}

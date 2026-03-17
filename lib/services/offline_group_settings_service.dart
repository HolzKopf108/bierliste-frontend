import 'package:bierliste/models/group_settings.dart';
import 'package:hive/hive.dart';

import 'group_settings_api_service.dart';

class OfflineGroupSettingsService {
  static const _boxName = 'group_settings_cache';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> saveGroupSettings(
    String userEmail,
    int groupId,
    GroupSettings groupSettings,
  ) async {
    final box = await _openBox();
    await box.put(
      _groupSettingsKey(userEmail, groupId),
      groupSettings.toJson(),
    );
  }

  static Future<GroupSettings?> getGroupSettings(
    String userEmail,
    int groupId,
  ) async {
    final box = await _openBox();
    final rawGroup = box.get(_groupSettingsKey(userEmail, groupId));
    if (rawGroup is! Map) {
      return null;
    }

    try {
      return GroupSettings.fromJson(Map<String, dynamic>.from(rawGroup));
    } catch (_) {
      await box.delete(_groupSettingsKey(userEmail, groupId));
      return null;
    }
  }

  static Future<GroupSettings> refreshGroupSettings(
    String userEmail,
    int groupId,
  ) async {
    final groupSettings = await GroupSettingsApiService().fetchGroupSettings(
      groupId,
    );
    await saveGroupSettings(userEmail, groupId, groupSettings);
    return groupSettings;
  }

  static Future<bool> syncPendingOperations(String userEmail) async {
    return true;
  }

  static String _groupSettingsKey(String userEmail, int groupId) {
    return 'group_settings_cache_${userEmail}_$groupId';
  }
}

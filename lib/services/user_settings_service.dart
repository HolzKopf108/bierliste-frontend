import 'dart:convert';
import 'package:bierliste/services/user_settings_api_service.dart';
import 'package:hive/hive.dart';
import '../models/user_settings.dart';

class UserSettingsService {
  static const _boxName = 'user_settings_box';
  static const _key = 'user_settings';

  static Future<Box<UserSettings>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<UserSettings>(_boxName);
    } else {
      return await Hive.openBox<UserSettings>(_boxName);
    }
  }

  static Future<UserSettings?> load() async {
    final box = await _openBox();
    final settings = box.get(_key);

    await updateSettings(
      theme: settings?.theme ?? 'system',
      autoSyncEnabled: settings?.autoSyncEnabled ?? true,
    );

    return box.get(_key);
  }

  static Future<void> save(UserSettings settings) async {
    final box = await _openBox();
    await box.put(_key, settings);
  }

  static Future<String?> updateSettings({
    required String theme,
    required bool autoSyncEnabled,
  }) async {
    final lastUpdated = DateTime.now();

    try {
      final response = await UserSettingsApiService().updateSettings(theme, autoSyncEnabled, lastUpdated);
      final body = jsonDecode(response.body);

      saveLokalSettings(
        body["theme"] ?? theme,
        body["autoSyncEnabled"] ?? autoSyncEnabled,
        body["lastUpdated"] != null ? DateTime.parse(body["lastUpdated"]) : lastUpdated,
      );

      return body["error"];
    }
    catch(e) {
      saveLokalSettings(theme, autoSyncEnabled, lastUpdated);
      return null;
    }
  }

  static void saveLokalSettings(
    String theme,
    bool autoSyncEnabled,
    DateTime lastUpdated,
  ) async {
    final box = await _openBox();
    final settings = box.get(_key);
      if (settings != null) {
        settings
          ..theme = theme
          ..autoSyncEnabled = autoSyncEnabled
          ..lastUpdated = lastUpdated;
        await settings.save();
      } else {
        final newSettings = UserSettings(
          theme: theme,
          autoSyncEnabled: autoSyncEnabled,
          lastUpdated: lastUpdated,
        );
        await box.put(_key, newSettings);
      }
  }
}

import 'dart:convert';
import 'package:bierliste/services/user_settings_api_service.dart';
import 'package:flutter/material.dart';
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

  static Future<UserSettings> load() async {
    final box = await _openBox();
    var settings = box.get(_key);

    if (settings == null) {

      debugPrint('settings sind null');

      final data = await UserSettingsApiService().getUserSettings();

      if (data == null) {

        debugPrint('data ist null');

        return await saveLokalSettings(
          'system',
          true,
          DateTime.now(),
        );
      }

      debugPrint('NEUE LOKALE SETTINGS ERSTELLEN');
      debugPrint(data["theme"]);
      
      return await saveLokalSettings(
        data["theme"], 
        data["autoSyncEnabled"], 
        DateTime.parse(data["lastUpdated"])
      );
    }

    debugPrint('settings sind da');
    debugPrint(settings.theme);

    await updateSettings(
      theme: settings.theme,
      autoSyncEnabled: settings.autoSyncEnabled,
    );

    return box.get(_key) ?? await saveLokalSettings(settings.theme, settings.autoSyncEnabled, settings.lastUpdated);
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

      await saveLokalSettings(
        body["theme"] ?? theme,
        body["autoSyncEnabled"] ?? autoSyncEnabled,
        body["lastUpdated"] != null ? DateTime.parse(body["lastUpdated"]) : lastUpdated,
      );

      return body["error"];
    }
    catch(e) {
      await saveLokalSettings(theme, autoSyncEnabled, lastUpdated);
      return null;
    }
  }

  static Future<UserSettings> saveLokalSettings(
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
        return settings;
      } else {
        final newSettings = UserSettings(
          theme: theme,
          autoSyncEnabled: autoSyncEnabled,
          lastUpdated: lastUpdated,
        );
        await box.put(_key, newSettings);
        return newSettings;
      }
  }

  static Future<void> clearLocalSettings() async {
    final box = await _openBox();
    await box.delete(_key);
  }
}

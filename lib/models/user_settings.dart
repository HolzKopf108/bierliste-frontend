import 'package:hive/hive.dart';

part 'user_settings.g.dart';

@HiveType(typeId: 1)
class UserSettings extends HiveObject {
  @HiveField(0)
  String theme;

  @HiveField(1)
  bool autoSyncEnabled;

  @HiveField(2)
  DateTime lastUpdated;

  UserSettings({
    required this.theme,
    required this.autoSyncEnabled,
    required this.lastUpdated,
  });
}

import 'package:hive/hive.dart';

part 'user_settings.g.dart';

@HiveType(typeId: 1)
class UserSettings extends HiveObject {
  @HiveField(0)
  String theme;

  @HiveField(2)
  DateTime lastUpdated;

  UserSettings({required this.theme, required this.lastUpdated});
}

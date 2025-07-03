import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 2)
class User extends HiveObject {
  @HiveField(0)
  String email;

  @HiveField(1)
  String username;

  @HiveField(2)
  DateTime lastUpdated;

  @HiveField(3)
  bool googleUser;

  User({
    required this.email,
    required this.username,
    required this.lastUpdated,
    required this.googleUser,
  });
}

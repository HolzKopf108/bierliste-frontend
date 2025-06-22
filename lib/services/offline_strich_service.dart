import 'package:hive/hive.dart';

class OfflineStrichService {
  static const _boxName = 'offline_striche';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return await Hive.openBox(_boxName);
    }
  }

  static Future<void> saveLastOnlineCounter(String userEmail, int count) async {
    final box = await _openBox();
    await box.put('${userEmail}_lastOnlineCount', count);
  }

  static Future<int> getLastOnlineCounter(String userEmail) async {
    final box = await _openBox();
    return box.get('${userEmail}_lastOnlineCount', defaultValue: 0);
  }

  static Future<void> addPendingStriche(String userEmail, int count) async {
    final box = await _openBox();
    final List<int> list = (box.get('${userEmail}_pending') as List?)?.cast<int>() ?? [];
    list.add(count);
    await box.put('${userEmail}_pending', list);
  }

  static Future<List<int>> getPendingStriche(String userEmail) async {
    final box = await _openBox();
    return (box.get('${userEmail}_pending') as List?)?.cast<int>() ?? [];
  }

  static Future<int> getPendingSum(String userEmail) async {
    final list = await getPendingStriche(userEmail);
    return list.fold<int>(0, (sum, x) => sum + x);
  }

  static Future<bool> hasPendingStriche(String userEmail) async {
    final list = await getPendingStriche(userEmail);
    return list.isNotEmpty;
  }

  static Future<void> clearPendingStriche(String userEmail) async {
    final box = await _openBox();
    await box.delete('${userEmail}_pending');
  }
}

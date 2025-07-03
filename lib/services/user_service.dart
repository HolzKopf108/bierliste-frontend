import 'package:bierliste/models/user.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/services/user_api_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class UserService {
  static const _boxName = 'user_box';
  static const _key = 'current_user';

  static Future<Box<User>> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<User>(_boxName);
    } else {
      return await Hive.openBox<User>(_boxName);
    }
  }

  static Future<User?> load() async {
    final box = await _openBox();
    final user = box.get(_key);

    if(user != null) {
      try {
        final data = await UserApiService().updateUsername(username: user.username, lastUpdated: user.lastUpdated, googleUser: user.googleUser);
        if (data == null) {
          return user;
        }
        user.username = data['username'];
        user.lastUpdated = DateTime.parse(data['lastUpdated']);
        await user.save();

        return user;
      } catch (_) {
        return user;
      }
    } 
    else {
      try {
        final data = await UserApiService().getUser();

        if (data == null) {
          return null;
        }

        final newUser = User(
                          email: data['email'], 
                          username: data['username'], 
                          lastUpdated: DateTime.parse(data['lastUpdated']), 
                          googleUser: data['googleUser']
                        );
        await box.put(_key, newUser);
        return newUser;
      } catch(e) {
        debugPrint(e.toString());
        return null;
      }
    }
  }

  static Future<void> updateUsername(String newUsername) async {
    final box = await _openBox();
    final user = box.get(_key);
    if (user != null) {
      final data = await UserApiService().updateUsername(username: newUsername, lastUpdated: DateTime.now(), googleUser: user.googleUser);

      if (data == null) {
        return;
      }

      user.username = data['username'];
      user.lastUpdated = DateTime.parse(data['lastUpdated']);
      await user.save();
    }
  }

  static Future<String?> updatePassword(String newPassword) async {
    return await UserApiService().updatePassword(newPassword: newPassword, lastUpdated: DateTime.now());
  }

  static Future<void> clear() async {
    final box = await _openBox();
    await box.delete(_key);
  }

  static Future<String?> deleteAccount(AuthProvider authProvider) async {
    final error = await UserApiService().deleteAccount();
    if (error == null) {
      await authProvider.logout();
    }

    return error;
  }
}

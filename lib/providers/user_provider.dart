import 'package:bierliste/main.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:bierliste/models/user.dart';
import 'package:bierliste/services/user_service.dart';
import 'package:provider/provider.dart';

class UserProvider with ChangeNotifier {
  User? _user;
  bool _loaded = false;

  User? get user => _user;
  bool get isLoaded => _loaded;

  Future<void> loadUser() async {
    _user = await UserService.load();
    
    if (_user == null) {
      final authProvider = Provider.of<AuthProvider>(
        navigatorKey.currentContext!,
        listen: false,
      );
      await authProvider.logout();
      return;
    }

    _loaded = true;
    notifyListeners();
  }

  void clearUser() {
    _user = null;
    _loaded = false;
    notifyListeners();
  }

  Future<void> updateUsername(String username) async {
    await UserService.updateUsername(username);
    await loadUser(); 
  }
}

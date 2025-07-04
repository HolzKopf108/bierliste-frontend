import 'package:bierliste/main.dart';
import 'package:bierliste/providers/sync_provider.dart';
import 'package:bierliste/providers/theme_provider.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:bierliste/services/user_service.dart';
import 'package:bierliste/services/user_settings_service.dart';
import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/token_service.dart';
import '../services/http_service.dart';
import '../services/connectivity_service.dart';

class AuthProvider with ChangeNotifier {
  bool _authenticated = false;
  String? _userEmail;
  bool _initialized = false;

  bool get isAuthenticated => _authenticated;
  String? get userEmail => _userEmail;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    final token = await TokenService.getAccessToken();
    final refresh = await TokenService.getRefreshToken();
    _userEmail = await TokenService.getUserEmail();

    if (token != null && refresh != null) {
      if (await ConnectivityService.isOnline()) {
        _authenticated = await HttpService.refreshTokens();
      } else {
        _authenticated = true;
      }
    } else {
      _authenticated = false;
    }

    if (_authenticated) {
      final userProvider = Provider.of<UserProvider>(navigatorKey.currentContext!, listen: false);
      await userProvider.loadUser();

      final themeProvider = Provider.of<ThemeProvider>(navigatorKey.currentContext!, listen: false);
      await themeProvider.loadTheme();

      final syncProvider = Provider.of<SyncProvider>(navigatorKey.currentContext!, listen: false);
      await syncProvider.loadAutoSyncEnabled();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> login(String accessToken, String refreshToken, String userEmail) async {
    await TokenService.saveTokens(accessToken, refreshToken, userEmail);
    _authenticated = true;
    _userEmail = userEmail;

    final userProvider = Provider.of<UserProvider>(navigatorKey.currentContext!, listen: false);
    await userProvider.loadUser();

    final themeProvider = Provider.of<ThemeProvider>(navigatorKey.currentContext!, listen: false);
    await themeProvider.loadTheme();

    final syncProvider = Provider.of<SyncProvider>(navigatorKey.currentContext!, listen: false);
    await syncProvider.loadAutoSyncEnabled();

    notifyListeners();
  }

  Future<void> logout() async {
    await TokenService.clearTokens();
    _authenticated = false;
    _userEmail = null;

    await UserService.clear();
    await UserSettingsService.clearLocalSettings();

    if (onLogoutCallback != null) {
      onLogoutCallback!();
    }

    safeGlobalPushNamedAndRemoveUntil('/login');

    final themeProvider = Provider.of<ThemeProvider>(navigatorKey.currentContext!, listen: false);
    themeProvider.initialize();

    final syncProvider = Provider.of<SyncProvider>(navigatorKey.currentContext!, listen: false);
    syncProvider.initialize();

    notifyListeners();
  }

  void Function()? onLogoutCallback;
}

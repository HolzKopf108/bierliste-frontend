import 'package:bierliste/main.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/providers/sync_provider.dart';
import 'package:bierliste/providers/theme_provider.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:bierliste/services/user_service.dart';
import 'package:bierliste/services/user_settings_service.dart';
import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/token_service.dart';
import '../services/connectivity_service.dart';

class AuthProvider with ChangeNotifier {
  bool _authenticated = false;
  String? _userEmail;
  bool _initialized = false;
  String? _authErrorMessage;

  bool get isAuthenticated => _authenticated;
  String? get userEmail => _userEmail;
  bool get isInitialized => _initialized;
  String? get authErrorMessage => _authErrorMessage;

  Future<void> initialize() async {
    final token = await TokenService.getAccessToken();
    final refresh = await TokenService.getRefreshToken();
    _userEmail = await TokenService.getUserEmail();
    _authErrorMessage = null;

    if (refresh != null) {
      if (await ConnectivityService.isOnline()) {
        final refreshResult = await HttpService.refreshTokens();
        if (refreshResult.isSuccess) {
          _authenticated = true;
          _userEmail = refreshResult.tokens!.userEmail;
        } else if (refreshResult.shouldLogout) {
          _authenticated = false;
          _authErrorMessage = refreshResult.message;
        } else if (refreshResult.isTechnicalFailure) {
          _authenticated = token != null && token.trim().isNotEmpty;
          _authErrorMessage = refreshResult.message;
        } else {
          _authenticated = false;
          _authErrorMessage = refreshResult.message;
        }
      } else {
        _authenticated = token != null && token.trim().isNotEmpty;
      }
    } else {
      _authenticated = false;
    }

    if (_authenticated) {
      final userProvider = Provider.of<UserProvider>(
        navigatorKey.currentContext!,
        listen: false,
      );
      await userProvider.loadUser();

      final themeProvider = Provider.of<ThemeProvider>(
        navigatorKey.currentContext!,
        listen: false,
      );
      await themeProvider.loadTheme();

      final syncProvider = Provider.of<SyncProvider>(
        navigatorKey.currentContext!,
        listen: false,
      );
      await syncProvider.loadAutoSyncEnabled();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> login(
    String accessToken,
    String refreshToken,
    String userEmail,
  ) async {
    await TokenService.saveTokens(accessToken, refreshToken, userEmail);
    _authenticated = true;
    _userEmail = userEmail;
    _authErrorMessage = null;

    final userProvider = Provider.of<UserProvider>(
      navigatorKey.currentContext!,
      listen: false,
    );
    await userProvider.loadUser();

    final themeProvider = Provider.of<ThemeProvider>(
      navigatorKey.currentContext!,
      listen: false,
    );
    await themeProvider.loadTheme();

    final syncProvider = Provider.of<SyncProvider>(
      navigatorKey.currentContext!,
      listen: false,
    );
    await syncProvider.loadAutoSyncEnabled();

    notifyListeners();
  }

  Future<void> logout({String? reason}) async {
    final logoutReason = reason ?? _authErrorMessage;

    await TokenService.clearTokens();
    _authenticated = false;
    _userEmail = null;
    _authErrorMessage = null;

    await UserService.clear();
    await UserSettingsService.clearLocalSettings();

    if (onLogoutCallback != null) {
      onLogoutCallback!();
    }

    safeGlobalPushNamedAndRemoveUntil('/login', arguments: logoutReason);

    final themeProvider = Provider.of<ThemeProvider>(
      navigatorKey.currentContext!,
      listen: false,
    );
    themeProvider.initialize();

    final syncProvider = Provider.of<SyncProvider>(
      navigatorKey.currentContext!,
      listen: false,
    );
    syncProvider.initialize();

    notifyListeners();
  }

  void Function()? onLogoutCallback;
}

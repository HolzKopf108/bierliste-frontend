import 'package:flutter/material.dart';
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

    _initialized = true;
    notifyListeners();
  }

  Future<void> login(String accessToken, String refreshToken, String userEmail) async {
    await TokenService.saveTokens(accessToken, refreshToken, userEmail);
    _authenticated = true;
    _userEmail = userEmail;
    notifyListeners();
  }

  Future<void> logout() async {
    await TokenService.clearTokens();
    _authenticated = false;
    _userEmail = null;
    notifyListeners();
  }
}

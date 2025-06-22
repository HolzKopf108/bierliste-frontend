import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenService {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  static const _userEmailKey = 'userEmail';
  static final _storage = FlutterSecureStorage();

  static Future<String?> getAccessToken() async => await _storage.read(key: _accessTokenKey);
  static Future<String?> getRefreshToken() async => await _storage.read(key: _refreshTokenKey);
  static Future<String?> getUserEmail() async => await _storage.read(key: _userEmailKey);

  static Future<void> saveTokens(String accessToken, String refreshToken, String userEmail) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _userEmailKey, value: userEmail);
  }

  static Future<void> clearTokens() async {
    await _storage.deleteAll();
  }
}

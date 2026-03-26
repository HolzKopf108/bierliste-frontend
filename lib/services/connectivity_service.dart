import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ConnectivityService {
  static Future<bool> Function()? testIsOnline;
  static Future<bool> Function(String url)? testIsServerOnline;
  static Future<bool> Function()? testIsDeviceOnline;

  static Future<bool> isOnline() async {
    final isOnlineOverride = testIsOnline;
    if (isOnlineOverride != null) {
      return isOnlineOverride();
    }

    if (!await isDeviceOnline()) return false;

    return await isServerOnline(
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.ping}',
    );
  }

  static Future<bool> isServerOnline(String url) async {
    final isServerOnlineOverride = testIsServerOnline;
    if (isServerOnlineOverride != null) {
      return isServerOnlineOverride(url);
    }

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isDeviceOnline() async {
    final isDeviceOnlineOverride = testIsDeviceOnline;
    if (isDeviceOnlineOverride != null) {
      return isDeviceOnlineOverride();
    }

    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }
}

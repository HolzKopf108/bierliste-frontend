import 'dart:async';
import 'package:bierliste/services/user_settings_service.dart';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

class SyncProvider with ChangeNotifier {
  bool _autoSyncEnabled = true;
  bool _actualOnline = false;
  bool _isSyncing = false;

  Timer? _monitorTimer;

  void Function()? onReconnected;

  bool get isAppOnline => _autoSyncEnabled && _actualOnline;
  bool get isServerOnline => _actualOnline;
  bool get isAutoSyncEnabled => _autoSyncEnabled;
  bool get isSyncing => _isSyncing;

  SyncProvider() {
    loadAutoSyncEnabled();
  }

  Future<void> loadAutoSyncEnabled() async {
    final loaded = await UserSettingsService.load();
    await setAutoSyncEnabled(loaded.autoSyncEnabled);
  }

  Future<String?> setAutoSyncEnabled(bool value) async {
    var currentSettings = await UserSettingsService.load();

    final error = await UserSettingsService.updateSettings(
      theme: currentSettings.theme,
      autoSyncEnabled: value,
    );

    currentSettings = await UserSettingsService.load();

    _autoSyncEnabled = currentSettings.autoSyncEnabled;
    notifyListeners();

    if (value) {
      startMonitoring();
    } else {
      stopMonitoring();
    }

    return error;
  }

  void setIsSyncing(bool value) {
    _isSyncing = value;
    notifyListeners();
  }

  void startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkOnlineStatus());
    _checkOnlineStatus();
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> forceCheck() async {
    await _checkOnlineStatus();
  }

  Future<void> _checkOnlineStatus() async {
    final isOnline = await ConnectivityService.isOnline();
    if (isOnline != _actualOnline) {
      _actualOnline = isOnline;
      notifyListeners();

      if (isAppOnline) {
        onReconnected?.call();
      }
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

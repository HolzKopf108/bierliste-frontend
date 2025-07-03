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
    _initialize();
  }

  void _initialize() async {
    final loaded = await UserSettingsService.load();
    setAutoSyncEnabled(loaded?.autoSyncEnabled ?? true);
  }

  void setAutoSyncEnabled(bool value) {
    _autoSyncEnabled = value;
    notifyListeners();

    if (value) {
      startMonitoring();
    } else {
      stopMonitoring();
    }
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

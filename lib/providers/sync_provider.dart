import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/connectivity_service.dart';
import '../services/pending_sync_service.dart';
import '../services/sync_debug_service.dart';
import '../services/token_service.dart';
import '../services/pending_sync_queue_service.dart';
import '../models/pending_sync_operation.dart';

class SyncProvider with ChangeNotifier {
  static const _monitorInterval = Duration(seconds: 10);

  bool _actualOnline = false;
  bool _isSyncing = false;
  bool _hasPendingSync = false;
  List<PendingSyncOperation> _operations = [];
  StreamSubscription<String>? _queueSubscription;
  bool _disposed = false;
  int _statusRead = 0;
  List<PendingSyncOperation> get problems => List.unmodifiable(_operations.where((operation) => operation.status == 'failed'));
  bool hasPendingForGroup(int groupId) => _operations.any((operation) => operation.groupId == groupId && operation.status != 'failed');
  bool hasProblemsForGroup(int groupId) => problems.any((operation) => operation.groupId == groupId);

  Timer? _monitorTimer;
  Future<bool> Function()? _syncHandler;
  Future<bool>? _syncInFlight;

  bool get isAppOnline => _actualOnline;
  bool get isServerOnline => _actualOnline;
  bool get isSyncing => _isSyncing;
  bool get hasPendingSync => _hasPendingSync;

  SyncProvider() {
    initialize();
  }

  void initialize() {
    _actualOnline = false;
    _isSyncing = false;
    _hasPendingSync = false;
    _operations = [];
    _queueSubscription ??= PendingSyncQueueService.changes.listen((_) {
      unawaited(refreshPendingSyncStatus());
    });
    notifyListeners();
    startMonitoring();
    unawaited(refreshPendingSyncStatus());
  }

  void registerSyncHandler(Future<bool> Function() handler) {
    _syncHandler = handler;
    unawaited(requestSync());
  }

  Future<void> markPendingSync() async {
    _setHasPendingSync(true);
    unawaited(requestSync(refreshPendingStatus: false));
  }

  Future<void> refreshPendingSyncStatus() async {
    final read = ++_statusRead;
    final userEmail = await TokenService.getUserEmail();
    final operations = userEmail == null ? <PendingSyncOperation>[] : await PendingSyncQueueService.getOperations(userEmail);
    if (_disposed || read != _statusRead) return;
    _operations = operations;
    _hasPendingSync = operations.any((operation) => operation.status != 'failed');
    notifyListeners();
  }

  Future<bool> requestSync({bool refreshPendingStatus = true}) async {
    if (refreshPendingStatus) {
      await refreshPendingSyncStatus();
    }

    await forceCheck();

    final userEmail = await TokenService.getUserEmail();
    final hasReadyOperations =
        userEmail != null &&
        await PendingSyncService.hasReadyOperations(userEmail);
    SyncDebugService.log(
      'SyncProvider',
      'requestSync',
      details: {
        'refreshPendingStatus': refreshPendingStatus,
        'hasPendingSync': _hasPendingSync,
        'actualOnline': _actualOnline,
        'isSyncing': _isSyncing,
        'hasReadyOperations': hasReadyOperations,
      },
    );

    if (!_hasPendingSync) {
      return true;
    }

    if (!_actualOnline) {
      return false;
    }

    if (!hasReadyOperations) {
      SyncDebugService.log(
        'SyncProvider',
        'sync skipped because only delayed retries remain',
        details: {'userEmail': userEmail},
      );
      return true;
    }

    return _performSync();
  }

  void startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(_monitorInterval, (_) {
      unawaited(_runMonitorCycle());
    });
    unawaited(_runMonitorCycle());
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> forceCheck() async {
    await _checkOnlineStatus();
  }

  Future<void> _runMonitorCycle() async {
    await refreshPendingSyncStatus();
    await _checkOnlineStatus();

    if (_hasPendingSync && _actualOnline) {
      final userEmail = await TokenService.getUserEmail();
      final hasReadyOperations =
          userEmail != null &&
          await PendingSyncService.hasReadyOperations(userEmail);
      SyncDebugService.log(
        'SyncProvider',
        'monitor cycle evaluated pending sync state',
        details: {
          'hasPendingSync': _hasPendingSync,
          'actualOnline': _actualOnline,
          'hasReadyOperations': hasReadyOperations,
        },
      );
      if (!hasReadyOperations) {
        return;
      }

      await _performSync();
    }
  }

  Future<void> _checkOnlineStatus() async {
    final isOnline = await ConnectivityService.isOnline();
    _setActualOnline(isOnline);
  }

  Future<bool> _performSync() async {
    if (_syncInFlight != null) {
      SyncDebugService.log('SyncProvider', 'reusing in-flight sync future');
      return _syncInFlight!;
    }

    final syncHandler = _syncHandler;
    if (syncHandler == null) {
      return false;
    }

    if (!_hasPendingSync || !_actualOnline) {
      return !_hasPendingSync;
    }

    final completer = Completer<bool>();
    _syncInFlight = completer.future;
    _setIsSyncing(true);

    try {
      SyncDebugService.log(
        'SyncProvider',
        'sync execution started',
        details: {
          'hasPendingSync': _hasPendingSync,
          'actualOnline': _actualOnline,
        },
      );
      final success = await syncHandler();
      await refreshPendingSyncStatus();
      SyncDebugService.log(
        'SyncProvider',
        'sync execution finished',
        details: {
          'success': success,
          'hasPendingSync': _hasPendingSync,
          'actualOnline': _actualOnline,
        },
      );
      if (success && _hasPendingSync && _actualOnline) {
        unawaited(requestSync(refreshPendingStatus: false));
      }
      completer.complete(success);
      return success;
    } catch (_) {
      await refreshPendingSyncStatus();
      SyncDebugService.log(
        'SyncProvider',
        'sync execution failed with exception',
        details: {
          'hasPendingSync': _hasPendingSync,
          'actualOnline': _actualOnline,
        },
      );
      completer.complete(false);
      return false;
    } finally {
      _syncInFlight = null;
      _setIsSyncing(false);
    }
  }

  void _setActualOnline(bool value) {
    if (_actualOnline == value) {
      return;
    }

    _actualOnline = value;
    notifyListeners();
  }

  void _setHasPendingSync(bool value) {
    if (_hasPendingSync == value) {
      return;
    }

    _hasPendingSync = value;
    notifyListeners();
  }

  void _setIsSyncing(bool value) {
    if (_isSyncing == value) {
      return;
    }

    _isSyncing = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _queueSubscription?.cancel();
    stopMonitoring();
    super.dispose();
  }
}

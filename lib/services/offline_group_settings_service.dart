import 'dart:async';

import 'package:bierliste/models/group_settings.dart';
import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:hive/hive.dart';

import 'group_settings_api_service.dart';

class OfflineGroupSettingsActionResult {
  final GroupSettings groupSettings;
  final bool hasPendingSync;
  final bool shouldReloadUi;
  final String? errorMessage;

  const OfflineGroupSettingsActionResult({
    required this.groupSettings,
    required this.hasPendingSync,
    this.shouldReloadUi = false,
    this.errorMessage,
  });
}

class OfflineGroupSettingsService {
  static const _boxName = 'group_settings_cache';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> saveGroupSettings(
    String userEmail,
    int groupId,
    GroupSettings groupSettings,
  ) async {
    final box = await _openBox();
    await box.put(
      _groupSettingsKey(userEmail, groupId),
      groupSettings.toJson(),
    );
  }

  static Future<GroupSettings?> getGroupSettings(
    String userEmail,
    int groupId,
  ) async {
    final box = await _openBox();
    final rawGroup = box.get(_groupSettingsKey(userEmail, groupId));
    if (rawGroup is! Map) {
      return null;
    }

    try {
      return GroupSettings.fromJson(Map<String, dynamic>.from(rawGroup));
    } catch (_) {
      await box.delete(_groupSettingsKey(userEmail, groupId));
      return null;
    }
  }

  static Future<void> clearGroupSettings(String userEmail, int groupId) async {
    final box = await _openBox();
    await box.delete(_groupSettingsKey(userEmail, groupId));
  }

  static Future<GroupSettings> refreshGroupSettings(
    String userEmail,
    int groupId,
  ) async {
    final groupSettings = await GroupSettingsApiService().fetchGroupSettings(
      groupId,
    );
    final effectiveSettings = await _applyPendingOverlay(
      userEmail,
      groupId,
      groupSettings,
    );
    await saveGroupSettings(userEmail, groupId, effectiveSettings);
    return effectiveSettings;
  }

  static Future<OfflineGroupSettingsActionResult> updateGroupSettings(
    String userEmail,
    int groupId,
    GroupSettings payload,
  ) async {
    await saveGroupSettings(userEmail, groupId, payload);
    final operation = await _queueSettingsUpdate(userEmail, groupId, payload);

    if (!await ConnectivityService.isOnline()) {
      return OfflineGroupSettingsActionResult(
        groupSettings: payload,
        hasPendingSync: true,
      );
    }

    try {
      final groupSettings = await GroupSettingsApiService().updateGroupSettings(
        groupId,
        payload,
      );
      await saveGroupSettings(userEmail, groupId, groupSettings);
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return OfflineGroupSettingsActionResult(
        groupSettings: groupSettings,
        hasPendingSync: false,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupSettingsApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        final currentSettings = await _refreshOrGetCached(
          userEmail,
          groupId,
          fallback: payload,
        );
        return OfflineGroupSettingsActionResult(
          groupSettings: currentSettings,
          hasPendingSync: false,
          shouldReloadUi: _shouldReloadUi(e.statusCode),
          errorMessage: _friendlyActionError(
            e,
            'Gruppeneinstellungen konnten nicht gespeichert werden',
          ),
        );
      }

      return OfflineGroupSettingsActionResult(
        groupSettings: payload,
        hasPendingSync: true,
      );
    } on TimeoutException {
      return OfflineGroupSettingsActionResult(
        groupSettings: payload,
        hasPendingSync: true,
      );
    } catch (_) {
      return OfflineGroupSettingsActionResult(
        groupSettings: payload,
        hasPendingSync: true,
      );
    }
  }

  static Future<bool> syncPendingOperations(
    String userEmail, {
    int? groupId,
  }) async {
    var operations = await PendingSyncQueueService.getOperations(userEmail);
    final syncableOperations = operations.where((operation) {
      if (operation.domain != PendingSyncOperation.domainGroupSettings) {
        return false;
      }
      if (operation.operationType != PendingSyncOperation.updateGroupSettings) {
        return false;
      }
      if (!operation.isReadyForSync) {
        return false;
      }
      if (groupId != null && operation.groupId != groupId) {
        return false;
      }
      return true;
    }).toList();

    if (syncableOperations.isEmpty) {
      return true;
    }

    var allSuccessful = true;

    for (final operation in syncableOperations) {
      if (!operations.any((entry) => entry.id == operation.id)) {
        continue;
      }

      try {
        final updatedSettings = await GroupSettingsApiService()
            .updateGroupSettings(
              operation.groupId,
              _settingsFromOperation(operation),
            );
        await saveGroupSettings(userEmail, operation.groupId, updatedSettings);
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        operations = await PendingSyncQueueService.getOperations(userEmail);
      } on UnauthorizedException {
        rethrow;
      } on GroupSettingsApiException catch (e) {
        allSuccessful = false;
        if (_isPermanentFailure(e.statusCode)) {
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          try {
            await refreshGroupSettings(userEmail, operation.groupId);
          } catch (_) {}
        } else {
          await PendingSyncQueueService.replaceOperation(
            userEmail,
            PendingSyncQueueService.scheduleRetry(operation),
          );
          operations = await PendingSyncQueueService.getOperations(userEmail);
        }
      } on TimeoutException {
        allSuccessful = false;
        await PendingSyncQueueService.replaceOperation(
          userEmail,
          PendingSyncQueueService.scheduleRetry(operation),
        );
        operations = await PendingSyncQueueService.getOperations(userEmail);
      } catch (_) {
        allSuccessful = false;
        await PendingSyncQueueService.replaceOperation(
          userEmail,
          PendingSyncQueueService.scheduleRetry(operation),
        );
        operations = await PendingSyncQueueService.getOperations(userEmail);
      }
    }

    return allSuccessful;
  }

  static String _groupSettingsKey(String userEmail, int groupId) {
    return 'group_settings_cache_${userEmail}_$groupId';
  }

  static Future<PendingSyncOperation> _queueSettingsUpdate(
    String userEmail,
    int groupId,
    GroupSettings payload,
  ) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    final existingOperation = operations
        .where((operation) {
          return operation.domain == PendingSyncOperation.domainGroupSettings &&
              operation.operationType ==
                  PendingSyncOperation.updateGroupSettings &&
              operation.groupId == groupId;
        })
        .cast<PendingSyncOperation?>()
        .firstWhere((_) => true, orElse: () => null);

    if (existingOperation != null) {
      final updatedOperation = existingOperation.copyWith(
        payload: payload.toJson(),
        retryCount: 0,
        clearNextAttemptAt: true,
      );
      await PendingSyncQueueService.replaceOperation(
        userEmail,
        updatedOperation,
      );
      return updatedOperation;
    }

    final operation = PendingSyncQueueService.createOperation(
      userEmail: userEmail,
      domain: PendingSyncOperation.domainGroupSettings,
      operationType: PendingSyncOperation.updateGroupSettings,
      groupId: groupId,
      payload: payload.toJson(),
    );
    await PendingSyncQueueService.addOperation(operation);
    return operation;
  }

  static Future<GroupSettings> _refreshOrGetCached(
    String userEmail,
    int groupId, {
    required GroupSettings fallback,
  }) async {
    try {
      return await refreshGroupSettings(userEmail, groupId);
    } catch (_) {
      return await getGroupSettings(userEmail, groupId) ?? fallback;
    }
  }

  static GroupSettings _settingsFromOperation(PendingSyncOperation operation) {
    return GroupSettings.fromJson(operation.payload);
  }

  static Future<GroupSettings> _applyPendingOverlay(
    String userEmail,
    int groupId,
    GroupSettings backendSettings,
  ) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    final pendingUpdate = operations
        .where((operation) {
          return operation.domain == PendingSyncOperation.domainGroupSettings &&
              operation.operationType ==
                  PendingSyncOperation.updateGroupSettings &&
              operation.groupId == groupId;
        })
        .cast<PendingSyncOperation?>()
        .firstWhere((_) => true, orElse: () => null);

    if (pendingUpdate == null) {
      return backendSettings;
    }

    return _settingsFromOperation(pendingUpdate);
  }

  static bool _isPermanentFailure(int? statusCode) {
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }

  static bool _shouldReloadUi(int? statusCode) {
    return statusCode == 403 || statusCode == 404;
  }

  static String _friendlyActionError(
    GroupSettingsApiException exception,
    String fallbackMessage,
  ) {
    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Gruppe nicht gefunden / kein Zugriff';
      default:
        final message = exception.message.trim();
        return message.isNotEmpty ? message : fallbackMessage;
    }
  }
}

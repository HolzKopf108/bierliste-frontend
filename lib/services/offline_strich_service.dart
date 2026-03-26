import 'package:bierliste/models/confirmed_counter_increment.dart';
import 'package:bierliste/models/offline_counter_action_result.dart';
import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_counter_api_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:bierliste/services/sync_debug_service.dart';
import 'package:hive/hive.dart';

class OfflineStrichService {
  static const _boxName = 'offline_striche';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return await Hive.openBox(_boxName);
    }
  }

  static Future<void> saveLastOnlineCounter(
    String userEmail,
    int groupId,
    int count, {
    int? targetUserId,
  }) async {
    final box = await _openBox();
    await box.put(
      _lastOnlineCounterKey(userEmail, groupId, targetUserId),
      count,
    );
  }

  static Future<int> getLastOnlineCounter(
    String userEmail,
    int groupId, {
    int? targetUserId,
  }) async {
    final box = await _openBox();
    return box.get(
      _lastOnlineCounterKey(userEmail, groupId, targetUserId),
      defaultValue: 0,
    );
  }

  static Future<void> saveConfirmedIncrement(
    String userEmail,
    ConfirmedCounterIncrement increment,
  ) async {
    final box = await _openBox();
    await box.put(
      _confirmedIncrementKey(
        userEmail,
        increment.groupId,
        increment.localOperationId,
      ),
      increment.toJson(),
    );
    SyncDebugService.log(
      'OfflineStrichService',
      'confirmed increment saved',
      details: {
        'userEmail': userEmail,
        'groupId': increment.groupId,
        'localOperationId': increment.localOperationId,
        'incrementRequestId': increment.incrementRequestId,
        'undoExpiresAt': increment.undoExpiresAt.toIso8601String(),
        'targetUserId': increment.targetUserId,
      },
    );
  }

  static Future<ConfirmedCounterIncrement?> getConfirmedIncrement(
    String userEmail,
    String localOperationId, {
    required int groupId,
  }) async {
    final box = await _openBox();
    final rawValue = box.get(
      _confirmedIncrementKey(userEmail, groupId, localOperationId),
    );
    if (rawValue is! Map) {
      SyncDebugService.log(
        'OfflineStrichService',
        'confirmed increment missing',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'localOperationId': localOperationId,
        },
      );
      return null;
    }

    try {
      final increment = ConfirmedCounterIncrement.fromJson(
        Map<String, dynamic>.from(rawValue),
      );
      SyncDebugService.log(
        'OfflineStrichService',
        'confirmed increment loaded',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'localOperationId': localOperationId,
          'incrementRequestId': increment.incrementRequestId,
        },
      );
      return increment;
    } catch (_) {
      await box.delete(
        _confirmedIncrementKey(userEmail, groupId, localOperationId),
      );
      SyncDebugService.log(
        'OfflineStrichService',
        'invalid confirmed increment removed',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'localOperationId': localOperationId,
        },
      );
      return null;
    }
  }

  static Future<void> removeConfirmedIncrement(
    String userEmail,
    int groupId,
    String localOperationId,
  ) async {
    final box = await _openBox();
    await box.delete(
      _confirmedIncrementKey(userEmail, groupId, localOperationId),
    );
    SyncDebugService.log(
      'OfflineStrichService',
      'confirmed increment removed',
      details: {
        'userEmail': userEmail,
        'groupId': groupId,
        'localOperationId': localOperationId,
      },
    );
  }

  static Future<void> clearGroupData(String userEmail, int groupId) async {
    final box = await _openBox();
    final matchingKeys = box.keys.where((key) {
      final normalizedKey = key.toString();
      return normalizedKey.startsWith(
            'counter_cache_${userEmail}_${groupId}_',
          ) ||
          normalizedKey.startsWith(
            'confirmed_increment_${userEmail}_${groupId}_',
          );
    }).toList();
    await box.deleteAll(matchingKeys);
  }

  static Future<PendingSyncOperation> addPendingOwnCounterIncrement(
    String userEmail,
    int groupId,
    int amount,
  ) async {
    final operation = PendingSyncQueueService.createOperation(
      userEmail: userEmail,
      domain: PendingSyncOperation.domainCounter,
      operationType: PendingSyncOperation.incrementOwnCounter,
      groupId: groupId,
      payload: {'amount': amount},
    );
    await PendingSyncQueueService.addOperation(operation);
    return operation;
  }

  static Future<OfflineCounterActionResult> undoOwnCounterIncrement(
    String userEmail,
    int groupId,
    String localOperationId,
    int amount, {
    required bool isSyncing,
  }) async {
    final allOperations = await PendingSyncQueueService.getOperations(
      userEmail,
    );
    final confirmed = await getConfirmedIncrement(
      userEmail,
      localOperationId,
      groupId: groupId,
    );
    final existingUndoOperation = _findUndoOwnOperation(
      allOperations,
      localOperationId,
    );

    if (existingUndoOperation != null) {
      return OfflineCounterActionResult(
        count: await _effectiveOwnCounterCount(userEmail, groupId),
        hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
          userEmail,
        ),
      );
    }

    if (confirmed != null) {
      final undoExpiresAt = confirmed.undoExpiresAt;
      if (_isUndoExpired(undoExpiresAt)) {
        await removeConfirmedIncrement(userEmail, groupId, localOperationId);
        return OfflineCounterActionResult(
          count: await _effectiveOwnCounterCount(userEmail, groupId),
          hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
            userEmail,
          ),
          errorMessage: 'Undo-Zeitfenster abgelaufen',
        );
      }

      final undoOperation = PendingSyncQueueService.createOperation(
        userEmail: userEmail,
        domain: PendingSyncOperation.domainCounter,
        operationType: PendingSyncOperation.undoOwnCounterIncrement,
        groupId: groupId,
        payload: {
          'localOperationId': localOperationId,
          'amount': amount,
          'localStrichDelta': -amount,
          'incrementRequestId': confirmed.incrementRequestId,
          'undoExpiresAt': undoExpiresAt.toUtc().toIso8601String(),
        },
      );
      await PendingSyncQueueService.addOperation(undoOperation);

      final isOnline = await ConnectivityService.isOnline();
      if (!isOnline || isSyncing) {
        return OfflineCounterActionResult(
          count: await _effectiveOwnCounterCount(userEmail, groupId),
          hasPendingSync: true,
        );
      }

      try {
        final response = await GroupCounterApiService().undoCounterIncrement(
          groupId,
          confirmed.incrementRequestId,
        );
        await PendingSyncQueueService.removeOperations(userEmail, [
          undoOperation.id,
        ]);
        await removeConfirmedIncrement(userEmail, groupId, localOperationId);
        await saveLastOnlineCounter(userEmail, groupId, response.count);
        return OfflineCounterActionResult(
          count: await _effectiveOwnCounterCount(userEmail, groupId),
          hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
            userEmail,
          ),
        );
      } on UnauthorizedException {
        rethrow;
      } on GroupCounterApiException catch (e) {
        if (_isPermanentFailure(e.statusCode)) {
          await PendingSyncQueueService.removeOperations(userEmail, [
            undoOperation.id,
          ]);
          await removeConfirmedIncrement(userEmail, groupId, localOperationId);
          return OfflineCounterActionResult(
            count: await _effectiveOwnCounterCount(userEmail, groupId),
            hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
              userEmail,
            ),
            errorMessage: _friendlyUndoError(e),
          );
        }

        return OfflineCounterActionResult(
          count: await _effectiveOwnCounterCount(userEmail, groupId),
          hasPendingSync: true,
        );
      } catch (_) {
        return OfflineCounterActionResult(
          count: await _effectiveOwnCounterCount(userEmail, groupId),
          hasPendingSync: true,
        );
      }
    }

    final originalOperation = allOperations
        .cast<PendingSyncOperation?>()
        .firstWhere((operation) {
          return operation != null &&
              operation.id == localOperationId &&
              operation.domain == PendingSyncOperation.domainCounter &&
              operation.operationType ==
                  PendingSyncOperation.incrementOwnCounter &&
              operation.groupId == groupId;
        }, orElse: () => null);

    if (originalOperation != null && !isSyncing) {
      await PendingSyncQueueService.removeOperations(userEmail, [
        originalOperation.id,
      ]);
      return OfflineCounterActionResult(
        count: await _effectiveOwnCounterCount(userEmail, groupId),
        hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
          userEmail,
        ),
      );
    }

    if (originalOperation != null) {
      final undoOperation = PendingSyncQueueService.createOperation(
        userEmail: userEmail,
        domain: PendingSyncOperation.domainCounter,
        operationType: PendingSyncOperation.undoOwnCounterIncrement,
        groupId: groupId,
        payload: {
          'localOperationId': localOperationId,
          'amount': amount,
          'localStrichDelta': -amount,
        },
      );
      await PendingSyncQueueService.addOperation(undoOperation);
      return OfflineCounterActionResult(
        count: await _effectiveOwnCounterCount(userEmail, groupId),
        hasPendingSync: true,
      );
    }

    return OfflineCounterActionResult(
      count: await _effectiveOwnCounterCount(userEmail, groupId),
      hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
        userEmail,
      ),
      errorMessage: 'Strich kann gerade nicht rückgängig gemacht werden',
    );
  }

  static Future<List<PendingSyncOperation>> getPendingCounterOperations(
    String userEmail,
  ) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    return operations.where((operation) {
      return operation.domain == PendingSyncOperation.domainCounter &&
          (operation.operationType ==
                  PendingSyncOperation.incrementOwnCounter ||
              operation.operationType ==
                  PendingSyncOperation.undoOwnCounterIncrement);
    }).toList();
  }

  static Future<bool> syncPendingOperations(
    String userEmail, {
    int? groupId,
  }) async {
    var operations = await PendingSyncQueueService.getOperations(userEmail);
    operations = await _removeLocallyUndoneOwnIncrements(
      userEmail,
      operations,
      groupId: groupId,
    );

    final syncableOperations = operations.where((operation) {
      if (operation.domain != PendingSyncOperation.domainCounter) {
        return false;
      }
      if (operation.operationType != PendingSyncOperation.incrementOwnCounter &&
          operation.operationType !=
              PendingSyncOperation.undoOwnCounterIncrement) {
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

      if (operation.operationType == PendingSyncOperation.incrementOwnCounter) {
        try {
          final counter = await GroupCounterApiService()
              .incrementMyGroupCounter(operation.groupId, _amount(operation));
          await saveLastOnlineCounter(
            userEmail,
            operation.groupId,
            counter.count,
          );
          await saveConfirmedIncrement(
            userEmail,
            ConfirmedCounterIncrement(
              localOperationId: operation.id,
              groupId: operation.groupId,
              amount: _amount(operation),
              incrementRequestId: counter.incrementRequestId,
              undoExpiresAt: counter.undoExpiresAt,
              affectsCurrentUser: true,
            ),
          );
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
        } on UnauthorizedException {
          rethrow;
        } on GroupCounterApiException catch (e) {
          allSuccessful = false;
          if (_isPermanentFailure(e.statusCode)) {
            await PendingSyncQueueService.removeOperations(userEmail, [
              operation.id,
            ]);
          } else {
            await PendingSyncQueueService.replaceOperation(
              userEmail,
              PendingSyncQueueService.scheduleRetry(operation),
            );
          }
          operations = await PendingSyncQueueService.getOperations(userEmail);
        } catch (_) {
          allSuccessful = false;
          await PendingSyncQueueService.replaceOperation(
            userEmail,
            PendingSyncQueueService.scheduleRetry(operation),
          );
          operations = await PendingSyncQueueService.getOperations(userEmail);
        }
        continue;
      }

      final syncResult = await _syncUndoOwnCounterOperation(
        userEmail,
        operation,
        operations,
      );
      operations = syncResult.operations;
      if (!syncResult.successful) {
        allSuccessful = false;
      }
    }

    return allSuccessful;
  }

  static Future<void> clearPendingCounterOperations(String userEmail) async {
    final allOperations = await PendingSyncQueueService.getOperations(
      userEmail,
    );
    final filtered = allOperations.where((operation) {
      return operation.domain != PendingSyncOperation.domainCounter ||
          (operation.operationType !=
                  PendingSyncOperation.incrementOwnCounter &&
              operation.operationType !=
                  PendingSyncOperation.undoOwnCounterIncrement);
    }).toList();
    await PendingSyncQueueService.saveOperations(userEmail, filtered);
  }

  static Future<void> removePendingCounterOperations(
    String userEmail,
    Iterable<String> operationIds,
  ) {
    return PendingSyncQueueService.removeOperations(userEmail, operationIds);
  }

  static Future<int> getPendingSum(
    String userEmail,
    int groupId, {
    int? targetUserId,
  }) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    return operations
        .where((operation) {
          if (operation.groupId != groupId) {
            return false;
          }

          if (operation.domain == PendingSyncOperation.domainCounter) {
            return targetUserId == null &&
                (operation.operationType ==
                        PendingSyncOperation.incrementOwnCounter ||
                    operation.operationType ==
                        PendingSyncOperation.undoOwnCounterIncrement);
          }

          if (operation.domain != PendingSyncOperation.domainGroupUsers ||
              !_isMemberStrichOperation(operation)) {
            return false;
          }

          if (targetUserId != null) {
            return _targetUserId(operation) == targetUserId;
          }

          return operation.payload['affectsCurrentUser'] == true;
        })
        .fold<int>(0, (sum, operation) => sum + _pendingCountDelta(operation));
  }

  static Future<bool> hasPendingCounterOperations(String userEmail) async {
    final list = await getPendingCounterOperations(userEmail);
    return list.isNotEmpty;
  }

  static Future<int> _effectiveOwnCounterCount(
    String userEmail,
    int groupId,
  ) async {
    final lastOnlineCount = await getLastOnlineCounter(userEmail, groupId);
    final pendingCount = await getPendingSum(userEmail, groupId);
    return lastOnlineCount + pendingCount;
  }

  static Future<List<PendingSyncOperation>> _removeLocallyUndoneOwnIncrements(
    String userEmail,
    List<PendingSyncOperation> operations, {
    int? groupId,
  }) async {
    final undoOperationsByLocalId = <String, List<PendingSyncOperation>>{};
    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainCounter ||
          operation.operationType !=
              PendingSyncOperation.undoOwnCounterIncrement) {
        continue;
      }

      if (groupId != null && operation.groupId != groupId) {
        continue;
      }

      final localOperationId = _localOperationId(operation);
      if (localOperationId == null || localOperationId.isEmpty) {
        continue;
      }

      undoOperationsByLocalId
          .putIfAbsent(localOperationId, () => [])
          .add(operation);
    }

    if (undoOperationsByLocalId.isEmpty) {
      return operations;
    }

    final idsToRemove = <String>{};
    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainCounter ||
          operation.operationType != PendingSyncOperation.incrementOwnCounter) {
        continue;
      }
      if (groupId != null && operation.groupId != groupId) {
        continue;
      }

      final matchingUndoOperations = undoOperationsByLocalId[operation.id];
      if (matchingUndoOperations == null || matchingUndoOperations.isEmpty) {
        continue;
      }

      final confirmed = await getConfirmedIncrement(
        userEmail,
        operation.id,
        groupId: operation.groupId,
      );
      idsToRemove.add(operation.id);
      if (confirmed == null) {
        idsToRemove.addAll(matchingUndoOperations.map((entry) => entry.id));
      }
    }

    if (idsToRemove.isEmpty) {
      return operations;
    }

    await PendingSyncQueueService.removeOperations(userEmail, idsToRemove);
    return PendingSyncQueueService.getOperations(userEmail);
  }

  static Future<_UndoSyncResult> _syncUndoOwnCounterOperation(
    String userEmail,
    PendingSyncOperation operation,
    List<PendingSyncOperation> operations,
  ) async {
    final localOperationId = _localOperationId(operation);
    if (localOperationId == null || localOperationId.isEmpty) {
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return _UndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        true,
      );
    }

    final confirmed = await getConfirmedIncrement(
      userEmail,
      localOperationId,
      groupId: operation.groupId,
    );
    if (confirmed == null) {
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return _UndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        true,
      );
    }

    final undoExpiresAt = _undoExpiresAt(operation, confirmed);
    if (_isUndoExpired(undoExpiresAt)) {
      await removeConfirmedIncrement(
        userEmail,
        operation.groupId,
        localOperationId,
      );
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return _UndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        false,
      );
    }

    try {
      final response = await GroupCounterApiService().undoCounterIncrement(
        operation.groupId,
        confirmed.incrementRequestId,
      );
      await saveLastOnlineCounter(userEmail, operation.groupId, response.count);
      await removeConfirmedIncrement(
        userEmail,
        operation.groupId,
        localOperationId,
      );
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return _UndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        true,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupCounterApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        await removeConfirmedIncrement(
          userEmail,
          operation.groupId,
          localOperationId,
        );
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        return _UndoSyncResult(
          await PendingSyncQueueService.getOperations(userEmail),
          false,
        );
      }

      await PendingSyncQueueService.replaceOperation(
        userEmail,
        PendingSyncQueueService.scheduleUndoRetry(operation, undoExpiresAt),
      );
      return _UndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        false,
      );
    } catch (_) {
      await PendingSyncQueueService.replaceOperation(
        userEmail,
        PendingSyncQueueService.scheduleUndoRetry(operation, undoExpiresAt),
      );
      return _UndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        false,
      );
    }
  }

  static PendingSyncOperation? _findUndoOwnOperation(
    List<PendingSyncOperation> operations,
    String localOperationId,
  ) {
    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainCounter ||
          operation.operationType !=
              PendingSyncOperation.undoOwnCounterIncrement) {
        continue;
      }

      if (_localOperationId(operation) == localOperationId) {
        return operation;
      }
    }

    return null;
  }

  static String? _localOperationId(PendingSyncOperation operation) {
    final rawValue = operation.payload['localOperationId'];
    if (rawValue == null) {
      return null;
    }

    final normalizedValue = rawValue.toString().trim();
    if (normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  static DateTime _undoExpiresAt(
    PendingSyncOperation operation,
    ConfirmedCounterIncrement confirmed,
  ) {
    final rawValue = operation.payload['undoExpiresAt'];
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return DateTime.parse(rawValue).toUtc();
    }
    return confirmed.undoExpiresAt.toUtc();
  }

  static String _friendlyUndoError(GroupCounterApiException exception) {
    final normalizedMessage = exception.message.trim().toLowerCase();
    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Strich-Request nicht gefunden';
      case 409:
        if (normalizedMessage.contains('zeitfenster') ||
            normalizedMessage.contains('abgelaufen')) {
          return 'Undo-Zeitfenster abgelaufen';
        }
        if (normalizedMessage.contains('rückgängig') ||
            normalizedMessage.contains('rueckgaengig')) {
          return 'Strich-Request kann nicht mehr rückgängig gemacht werden';
        }
        return exception.message.trim().isNotEmpty
            ? exception.message.trim()
            : 'Strich konnte nicht rückgängig gemacht werden';
      default:
        return exception.message.trim().isNotEmpty
            ? exception.message.trim()
            : 'Strich konnte nicht rückgängig gemacht werden';
    }
  }

  static String _lastOnlineCounterKey(
    String userEmail,
    int groupId,
    int? targetUserId,
  ) {
    return 'counter_cache_${userEmail}_${groupId}_${targetUserId ?? 'me'}';
  }

  static String _confirmedIncrementKey(
    String userEmail,
    int groupId,
    String localOperationId,
  ) {
    return 'confirmed_increment_${userEmail}_${groupId}_$localOperationId';
  }

  static int _amount(PendingSyncOperation operation) {
    final value = operation.payload['amount'];
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  static int _pendingCountDelta(PendingSyncOperation operation) {
    if (operation.domain == PendingSyncOperation.domainCounter) {
      if (operation.operationType == PendingSyncOperation.incrementOwnCounter) {
        return _amount(operation);
      }

      if (operation.operationType ==
          PendingSyncOperation.undoOwnCounterIncrement) {
        return _localStrichDelta(operation);
      }
    }

    return _localStrichDelta(operation);
  }

  static bool _isMemberStrichOperation(PendingSyncOperation operation) {
    if (operation.operationType ==
            PendingSyncOperation.incrementGroupMemberCounter ||
        operation.operationType ==
            PendingSyncOperation.undoGroupMemberCounterIncrement) {
      return true;
    }

    return operation.operationType ==
            PendingSyncOperation.settleGroupMemberMoney ||
        operation.operationType ==
            PendingSyncOperation.settleGroupMemberStriche;
  }

  static int _localStrichDelta(PendingSyncOperation operation) {
    final value = operation.payload['localStrichDelta'];
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  static int _targetUserId(PendingSyncOperation operation) {
    final value = operation.payload['targetUserId'];
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  static bool _isUndoExpired(DateTime undoExpiresAt) {
    return !DateTime.now().toUtc().isBefore(undoExpiresAt);
  }

  static bool _isPermanentFailure(int? statusCode) {
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }
}

class _UndoSyncResult {
  final List<PendingSyncOperation> operations;
  final bool successful;

  const _UndoSyncResult(this.operations, this.successful);
}

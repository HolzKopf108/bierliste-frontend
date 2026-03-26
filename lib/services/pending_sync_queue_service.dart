import 'dart:async';

import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/sync_debug_service.dart';
import 'package:hive/hive.dart';

class PendingSyncQueueService {
  static const _boxName = 'pending_sync_queue';
  static const _pendingOperationsKey = 'pending_sync_operations';
  static final Map<String, Future<void>> _mutationTails = {};

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> addOperation(PendingSyncOperation operation) async {
    await _withMutationLock(operation.userEmail, (box) async {
      final operations = _readOperationsFromBox(box, operation.userEmail);
      operations.add(operation);
      await _writeOperationsToBox(box, operation.userEmail, operations);
      SyncDebugService.log(
        'PendingSyncQueue',
        'operation added',
        details: {
          'userEmail': operation.userEmail,
          'operationType': operation.operationType,
          'operationId': operation.id,
          'groupId': operation.groupId,
          'queue': SyncDebugService.summarizeOperations(operations),
        },
      );
    });
  }

  static Future<List<PendingSyncOperation>> getOperations(
    String userEmail,
  ) async {
    final box = await _openBox();
    return _readOperationsFromBox(box, userEmail);
  }

  static Future<void> saveOperations(
    String userEmail,
    List<PendingSyncOperation> operations,
  ) async {
    await _withMutationLock(userEmail, (box) async {
      await _writeOperationsToBox(box, userEmail, operations);
      SyncDebugService.log(
        'PendingSyncQueue',
        'operations replaced',
        details: {
          'userEmail': userEmail,
          'queue': SyncDebugService.summarizeOperations(operations),
        },
      );
    });
  }

  static Future<void> removeOperations(
    String userEmail,
    Iterable<String> operationIds,
  ) async {
    await _withMutationLock(userEmail, (box) async {
      final operations = _readOperationsFromBox(box, userEmail);
      final ids = operationIds.toSet();
      final filtered = operations.where((operation) {
        return !ids.contains(operation.id);
      }).toList();
      await _writeOperationsToBox(box, userEmail, filtered);
      SyncDebugService.log(
        'PendingSyncQueue',
        'operations removed',
        details: {
          'userEmail': userEmail,
          'removedIds': ids.join(','),
          'queue': SyncDebugService.summarizeOperations(filtered),
        },
      );
    });
  }

  static Future<void> removeGroupOperations(
    String userEmail,
    int groupId,
  ) async {
    await _withMutationLock(userEmail, (box) async {
      final operations = _readOperationsFromBox(box, userEmail);
      final filtered = operations.where((operation) {
        return operation.groupId != groupId;
      }).toList();
      await _writeOperationsToBox(box, userEmail, filtered);
      SyncDebugService.log(
        'PendingSyncQueue',
        'group operations removed',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'queue': SyncDebugService.summarizeOperations(filtered),
        },
      );
    });
  }

  static Future<bool> hasPendingOperations(String userEmail) async {
    final operations = await getOperations(userEmail);
    return operations.isNotEmpty;
  }

  static Future<void> clearOperations(String userEmail) async {
    await _withMutationLock(userEmail, (box) async {
      await box.delete(_pendingOperationsStorageKey(userEmail));
      SyncDebugService.log(
        'PendingSyncQueue',
        'queue cleared',
        details: {'userEmail': userEmail},
      );
    });
  }

  static Future<void> replaceOperation(
    String userEmail,
    PendingSyncOperation updatedOperation,
  ) async {
    await _withMutationLock(userEmail, (box) async {
      final operations = _readOperationsFromBox(box, userEmail);
      var operationFound = false;
      final updatedOperations = operations.map((operation) {
        if (operation.id != updatedOperation.id) {
          return operation;
        }

        operationFound = true;
        return updatedOperation;
      }).toList();

      if (!operationFound) {
        SyncDebugService.log(
          'PendingSyncQueue',
          'replace skipped because operation was already removed',
          details: {
            'userEmail': userEmail,
            'operationId': updatedOperation.id,
            'operationType': updatedOperation.operationType,
          },
        );
        return;
      }

      await _writeOperationsToBox(box, userEmail, updatedOperations);
      SyncDebugService.log(
        'PendingSyncQueue',
        'operation replaced',
        details: {
          'userEmail': userEmail,
          'operationId': updatedOperation.id,
          'operationType': updatedOperation.operationType,
          'retryCount': updatedOperation.retryCount,
          'nextAttemptAt': updatedOperation.nextAttemptAt?.toIso8601String(),
          'queue': SyncDebugService.summarizeOperations(updatedOperations),
        },
      );
    });
  }

  static PendingSyncOperation createOperation({
    required String userEmail,
    required String domain,
    required String operationType,
    required int groupId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    return PendingSyncOperation(
      id: _createOperationId(userEmail, domain, groupId),
      userEmail: userEmail,
      domain: domain,
      operationType: operationType,
      groupId: groupId,
      payload: payload,
      createdAt: DateTime.now().toUtc(),
    );
  }

  static PendingSyncOperation scheduleRetry(PendingSyncOperation operation) {
    final nextRetryCount = operation.retryCount + 1;
    final cappedPower = nextRetryCount > 6 ? 6 : nextRetryCount;
    final delay = Duration(seconds: 15 * (1 << (cappedPower - 1)));

    return operation.copyWith(
      retryCount: nextRetryCount,
      nextAttemptAt: DateTime.now().toUtc().add(delay),
    );
  }

  static PendingSyncOperation scheduleUndoRetry(
    PendingSyncOperation operation,
    DateTime undoExpiresAt,
  ) {
    final nextRetryCount = operation.retryCount + 1;
    const retryDelaysInSeconds = [2, 4, 8, 12];
    final delayIndex = nextRetryCount > retryDelaysInSeconds.length
        ? retryDelaysInSeconds.length - 1
        : nextRetryCount - 1;
    final desiredDelay = Duration(seconds: retryDelaysInSeconds[delayIndex]);
    final now = DateTime.now().toUtc();
    final latestUsefulRetryAt = undoExpiresAt.toUtc().subtract(
      const Duration(seconds: 1),
    );

    final nextAttemptAt = latestUsefulRetryAt.isAfter(now)
        ? now.add(desiredDelay).isAfter(latestUsefulRetryAt)
              ? latestUsefulRetryAt
              : now.add(desiredDelay)
        : undoExpiresAt.toUtc();

    return operation.copyWith(
      retryCount: nextRetryCount,
      nextAttemptAt: nextAttemptAt,
    );
  }

  static String _pendingOperationsStorageKey(String userEmail) {
    return '${userEmail}_$_pendingOperationsKey';
  }

  static List<PendingSyncOperation> _readOperationsFromBox(
    Box box,
    String userEmail,
  ) {
    final rawList =
        (box.get(_pendingOperationsStorageKey(userEmail)) as List?) ?? [];

    return rawList.whereType<Map>().map((entry) {
      return PendingSyncOperation.fromJson(Map<String, dynamic>.from(entry));
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<void> _writeOperationsToBox(
    Box box,
    String userEmail,
    List<PendingSyncOperation> operations,
  ) {
    return box.put(
      _pendingOperationsStorageKey(userEmail),
      operations.map((operation) => operation.toJson()).toList(),
    );
  }

  static Future<T> _withMutationLock<T>(
    String userEmail,
    Future<T> Function(Box box) action,
  ) async {
    final previousTail = _mutationTails[userEmail] ?? Future<void>.value();
    final completion = Completer<void>();
    _mutationTails[userEmail] = completion.future;

    await previousTail;

    try {
      final box = await _openBox();
      return await action(box);
    } finally {
      completion.complete();
      if (identical(_mutationTails[userEmail], completion.future)) {
        _mutationTails.remove(userEmail);
      }
    }
  }

  static String _createOperationId(
    String userEmail,
    String domain,
    int groupId,
  ) {
    return '${DateTime.now().microsecondsSinceEpoch}_${userEmail}_${domain}_$groupId';
  }
}

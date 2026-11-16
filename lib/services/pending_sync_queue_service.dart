import 'dart:async';

import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/sync_debug_service.dart';
import 'package:hive/hive.dart';

class PendingSyncQueueService {
  static const _boxName = 'pending_sync_queue';
  static const _pendingOperationsKey = 'pending_sync_operations';
  static final Map<String, Future<void>> _mutationTails = {};
  static final Map<String, int> _revisions = {};
  static final _changes = StreamController<String>.broadcast(sync: true);
  static Stream<String> get changes => _changes.stream;
  static int revision(String userEmail) => _revisions[userEmail] ?? 0;

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
    return _withMutationLock(userEmail, (box) async {
      final operations = _readOperationsFromBox(box, userEmail);
      final raw = box.get(_pendingOperationsStorageKey(userEmail));
      final entries = raw is Map ? raw['operations'] : raw;
      if (entries is List &&
          entries.whereType<Map>().any(
            (entry) => entry['clientEventId'] == null,
          )) {
        await _writeOperationsToBox(box, userEmail, operations);
      }
      return operations;
    });
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

  static Future<bool> removeUnsentCounterIncrement(
    String userEmail,
    String operationId,
  ) => _withMutationLock(userEmail, (box) async {
    final operations = _readOperationsFromBox(box, userEmail);
    final operation = operations
        .where((entry) => entry.id == operationId)
        .firstOrNull;
    if (operation == null ||
        operation.domain != PendingSyncOperation.domainCounter ||
        operation.operationType != PendingSyncOperation.incrementOwnCounter ||
        operation.status != 'pending' ||
        operation.retryCount != 0) {
      return false;
    }
    await _writeOperationsToBox(
      box,
      userEmail,
      operations.where((entry) => entry.id != operationId).toList(),
    );
    return true;
  });

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
    return operations.any((operation) => operation.status != 'failed');
  }

  static Future<void> clearOperations(String userEmail) async {
    await _withMutationLock(userEmail, (box) async {
      await box.delete(_pendingOperationsStorageKey(userEmail));
      _changes.add(userEmail);
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
    final clientEventId = PendingSyncOperation.newClientEventId();
    return PendingSyncOperation(
      id: clientEventId,
      clientEventId: clientEventId,
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
      status: 'pending',
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
    final raw = box.get(_pendingOperationsStorageKey(userEmail));
    final rawList = (raw is Map ? raw['operations'] : raw) as List? ?? [];

    return rawList.whereType<Map>().map((entry) {
      final operation = PendingSyncOperation.fromJson(
        Map<String, dynamic>.from(entry),
      );
      return operation.clientEventId == null
          ? operation.copyWith(
              clientEventId: PendingSyncOperation.newClientEventId(),
            )
          : operation;
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<void> _writeOperationsToBox(
    Box box,
    String userEmail,
    List<PendingSyncOperation> operations,
  ) async {
    final raw = box.get(_pendingOperationsStorageKey(userEmail));
    _revisions[userEmail] = revision(userEmail) + 1;
    await box.put(_pendingOperationsStorageKey(userEmail), {
      'operations': operations.map((operation) => operation.toJson()).toList(),
      'counters': raw is Map ? raw['counters'] ?? {} : {},
    });
    _changes.add(userEmail);
  }

  static Future<({int? count, List<PendingSyncOperation> operations})>
  counterSnapshot(String userEmail, int groupId) =>
      _withMutationLock(userEmail, (box) async {
        final raw = box.get(_pendingOperationsStorageKey(userEmail));
        final counters = raw is Map ? raw['counters'] : null;
        return (
          count: counters is Map ? counters['$groupId'] as int? : null,
          operations: _readOperationsFromBox(box, userEmail),
        );
      });

  static Future<void> recordCounter(
    String userEmail,
    int groupId,
    int count, {
    Iterable<String> acknowledgedIds = const [],
    int? expectedRevision,
  }) => _withMutationLock(userEmail, (box) async {
    if (expectedRevision != null && expectedRevision != revision(userEmail)) {
      return;
    }
    final currentOperations = _readOperationsFromBox(box, userEmail);
    if (expectedRevision != null &&
        currentOperations.any(
          (operation) =>
              operation.groupId == groupId &&
              operation.status != 'failed' &&
              operation.operationType ==
                  PendingSyncOperation.incrementOwnCounter &&
              (operation.status == 'syncing' || operation.retryCount > 0),
        )) {
      return;
    }
    final raw = box.get(_pendingOperationsStorageKey(userEmail));
    final counters = Map<String, dynamic>.from(
      raw is Map ? raw['counters'] ?? {} : {},
    );
    counters['$groupId'] = count;
    final ids = acknowledgedIds.toSet();
    final operations = currentOperations.where(
      (operation) => !ids.contains(operation.id),
    );
    await box.put(_pendingOperationsStorageKey(userEmail), {
      'operations': operations.map((operation) => operation.toJson()).toList(),
      'counters': counters,
    });
    _revisions[userEmail] = revision(userEmail) + 1;
    _changes.add(userEmail);
  });

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
}

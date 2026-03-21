import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/group_counter_api_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
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

  static Future<void> addPendingOwnCounterIncrement(
    String userEmail,
    int groupId,
    int amount,
  ) async {
    await PendingSyncQueueService.addOperation(
      PendingSyncQueueService.createOperation(
        userEmail: userEmail,
        domain: PendingSyncOperation.domainCounter,
        operationType: PendingSyncOperation.incrementOwnCounter,
        groupId: groupId,
        payload: {'amount': amount},
      ),
    );
  }

  static Future<List<PendingSyncOperation>> getPendingCounterOperations(
    String userEmail,
  ) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    return operations.where((operation) {
      return operation.domain == PendingSyncOperation.domainCounter &&
          operation.operationType == PendingSyncOperation.incrementOwnCounter;
    }).toList();
  }

  static Future<bool> syncPendingOperations(
    String userEmail, {
    int? groupId,
  }) async {
    final allOperations = await PendingSyncQueueService.getOperations(
      userEmail,
    );
    final syncableOperations = allOperations.where((operation) {
      if (operation.domain != PendingSyncOperation.domainCounter) {
        return false;
      }
      if (operation.operationType != PendingSyncOperation.incrementOwnCounter) {
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

    final groupedOperations = <int, List<PendingSyncOperation>>{};
    for (final operation in syncableOperations) {
      groupedOperations.putIfAbsent(operation.groupId, () => []).add(operation);
    }

    var allSuccessful = true;
    var operations = List<PendingSyncOperation>.from(allOperations);

    for (final entry in groupedOperations.entries) {
      final operationsForGroup = entry.value;
      final currentGroupId = entry.key;
      final totalAmount = operationsForGroup.fold<int>(
        0,
        (sum, operation) => sum + _amount(operation),
      );

      try {
        final counter = await GroupCounterApiService().incrementMyGroupCounter(
          currentGroupId,
          totalAmount,
        );
        await saveLastOnlineCounter(userEmail, currentGroupId, counter.count);
        final operationIds = operationsForGroup
            .map((operation) => operation.id)
            .toSet();
        operations = operations.where((operation) {
          return !operationIds.contains(operation.id);
        }).toList();
        await PendingSyncQueueService.saveOperations(userEmail, operations);
      } on UnauthorizedException {
        rethrow;
      } on GroupCounterApiException catch (e) {
        allSuccessful = false;
        if (_isPermanentFailure(e.statusCode)) {
          final operationIds = operationsForGroup
              .map((operation) => operation.id)
              .toSet();
          operations = operations.where((operation) {
            return !operationIds.contains(operation.id);
          }).toList();
        } else {
          final updatedIds = operationsForGroup
              .map((operation) => operation.id)
              .toSet();
          operations = operations.map((operation) {
            if (!updatedIds.contains(operation.id)) {
              return operation;
            }

            return PendingSyncQueueService.scheduleRetry(operation);
          }).toList();
        }
        await PendingSyncQueueService.saveOperations(userEmail, operations);
      } catch (_) {
        allSuccessful = false;
        final updatedIds = operationsForGroup
            .map((operation) => operation.id)
            .toSet();
        operations = operations.map((operation) {
          if (!updatedIds.contains(operation.id)) {
            return operation;
          }

          return PendingSyncQueueService.scheduleRetry(operation);
        }).toList();
        await PendingSyncQueueService.saveOperations(userEmail, operations);
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
          operation.operationType != PendingSyncOperation.incrementOwnCounter;
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
                operation.operationType ==
                    PendingSyncOperation.incrementOwnCounter;
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

  static String _lastOnlineCounterKey(
    String userEmail,
    int groupId,
    int? targetUserId,
  ) {
    return 'counter_cache_${userEmail}_${groupId}_${targetUserId ?? 'me'}';
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
    if (operation.domain == PendingSyncOperation.domainCounter &&
        operation.operationType == PendingSyncOperation.incrementOwnCounter) {
      return _amount(operation);
    }

    return _localStrichDelta(operation);
  }

  static bool _isMemberStrichOperation(PendingSyncOperation operation) {
    if (operation.operationType ==
        PendingSyncOperation.incrementGroupMemberCounter) {
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

  static bool _isPermanentFailure(int? statusCode) {
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }
}

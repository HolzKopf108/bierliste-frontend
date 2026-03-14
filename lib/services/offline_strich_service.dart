import 'package:bierliste/models/pending_counter_operation.dart';
import 'package:hive/hive.dart';

class OfflineStrichService {
  static const _boxName = 'offline_striche';
  static const _pendingOperationsKey = 'pending_counter_operations';

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
    final box = await _openBox();
    final operations = await getPendingCounterOperations(userEmail);
    operations.add(
      PendingCounterOperation(
        id: _createOperationId(userEmail, groupId),
        userEmail: userEmail,
        groupId: groupId,
        amount: amount,
        operationType: PendingCounterOperation.incrementOwnCounter,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await box.put(
      _pendingOperationsStorageKey(userEmail),
      operations.map((operation) => operation.toJson()).toList(),
    );
  }

  static Future<List<PendingCounterOperation>> getPendingCounterOperations(
    String userEmail,
  ) async {
    final box = await _openBox();
    final rawList =
        (box.get(_pendingOperationsStorageKey(userEmail)) as List?) ?? [];

    return rawList
        .whereType<Map>()
        .map(
          (entry) => PendingCounterOperation.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .toList();
  }

  static Future<int> getPendingSum(
    String userEmail,
    int groupId, {
    int? targetUserId,
  }) async {
    final list = await getPendingCounterOperations(userEmail);
    return list
        .where(
          (operation) =>
              operation.groupId == groupId &&
              operation.targetUserId == targetUserId &&
              operation.operationType ==
                  PendingCounterOperation.incrementOwnCounter,
        )
        .fold<int>(0, (sum, operation) => sum + operation.amount);
  }

  static Future<bool> hasPendingCounterOperations(String userEmail) async {
    final list = await getPendingCounterOperations(userEmail);
    return list.isNotEmpty;
  }

  static Future<void> removePendingCounterOperations(
    String userEmail,
    Iterable<String> operationIds,
  ) async {
    final box = await _openBox();
    final ids = operationIds.toSet();
    final operations = await getPendingCounterOperations(userEmail);
    final filtered = operations.where(
      (operation) => !ids.contains(operation.id),
    );
    await box.put(
      _pendingOperationsStorageKey(userEmail),
      filtered.map((operation) => operation.toJson()).toList(),
    );
  }

  static Future<void> clearPendingCounterOperations(String userEmail) async {
    final box = await _openBox();
    await box.delete(_pendingOperationsStorageKey(userEmail));
  }

  static String _lastOnlineCounterKey(
    String userEmail,
    int groupId,
    int? targetUserId,
  ) {
    return 'counter_cache_${userEmail}_${groupId}_${targetUserId ?? 'me'}';
  }

  static String _pendingOperationsStorageKey(String userEmail) {
    return '${userEmail}_$_pendingOperationsKey';
  }

  static String _createOperationId(String userEmail, int groupId) {
    return '${DateTime.now().microsecondsSinceEpoch}_${userEmail}_$groupId';
  }
}

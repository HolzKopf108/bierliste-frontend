import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:hive/hive.dart';

class PendingSyncQueueService {
  static const _boxName = 'pending_sync_queue';
  static const _pendingOperationsKey = 'pending_sync_operations';

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> addOperation(PendingSyncOperation operation) async {
    final operations = await getOperations(operation.userEmail);
    operations.add(operation);
    await saveOperations(operation.userEmail, operations);
  }

  static Future<List<PendingSyncOperation>> getOperations(
    String userEmail,
  ) async {
    final box = await _openBox();
    final rawList =
        (box.get(_pendingOperationsStorageKey(userEmail)) as List?) ?? [];

    return rawList
        .whereType<Map>()
        .map(
          (entry) =>
              PendingSyncOperation.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<void> saveOperations(
    String userEmail,
    List<PendingSyncOperation> operations,
  ) async {
    final box = await _openBox();
    await box.put(
      _pendingOperationsStorageKey(userEmail),
      operations.map((operation) => operation.toJson()).toList(),
    );
  }

  static Future<void> removeOperations(
    String userEmail,
    Iterable<String> operationIds,
  ) async {
    final operations = await getOperations(userEmail);
    final ids = operationIds.toSet();
    final filtered = operations.where(
      (operation) => !ids.contains(operation.id),
    );
    await saveOperations(userEmail, filtered.toList());
  }

  static Future<void> removeGroupOperations(
    String userEmail,
    int groupId,
  ) async {
    final operations = await getOperations(userEmail);
    final filtered = operations.where(
      (operation) => operation.groupId != groupId,
    );
    await saveOperations(userEmail, filtered.toList());
  }

  static Future<bool> hasPendingOperations(String userEmail) async {
    final operations = await getOperations(userEmail);
    return operations.isNotEmpty;
  }

  static Future<void> clearOperations(String userEmail) async {
    final box = await _openBox();
    await box.delete(_pendingOperationsStorageKey(userEmail));
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

  static String _pendingOperationsStorageKey(String userEmail) {
    return '${userEmail}_$_pendingOperationsKey';
  }

  static String _createOperationId(
    String userEmail,
    String domain,
    int groupId,
  ) {
    return '${DateTime.now().microsecondsSinceEpoch}_${userEmail}_${domain}_$groupId';
  }
}

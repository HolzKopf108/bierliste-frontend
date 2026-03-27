import 'dart:async';
import 'dart:io';

import 'package:bierliste/models/counter_increment_result.dart';
import 'package:bierliste/models/counter_undo_result.dart';
import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/providers/sync_provider.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/group_counter_api_service.dart';
import 'package:bierliste/services/offline_group_users_service.dart';
import 'package:bierliste/services/offline_strich_service.dart';
import 'package:bierliste/services/pending_sync_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:bierliste/services/sync_debug_service.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userEmail = 'sync-race@example.com';
  const groupId = 17;
  const targetUserId = 42;
  final undoExpiresAt = DateTime.utc(2026, 3, 30, 12, 0, 0);

  Directory? tempDir;

  Future<void> resetTestState() async {
    ConnectivityService.testIsOnline = null;
    ConnectivityService.testIsDeviceOnline = null;
    ConnectivityService.testIsServerOnline = null;
    GroupCounterApiService.testFetchMyGroupCounter = null;
    GroupCounterApiService.testIncrementMyGroupCounter = null;
    GroupCounterApiService.testIncrementGroupMemberCounter = null;
    GroupCounterApiService.testUndoCounterIncrement = null;
    GroupApiService.testFetchGroupMembers = null;
    TokenService.testGetUserEmail = null;
    SyncDebugService.clear();
    SyncDebugService.enabled = false;
    await Hive.close();
  }

  setUp(() async {
    await resetTestState();
    tempDir = await Directory.systemTemp.createTemp('bierliste_sync_race_');
    Hive.init(tempDir!.path);
  });

  tearDown(() async {
    await resetTestState();
    final directory = tempDir;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    tempDir = null;
  });

  test(
    'local own-counter undo removes unsynced increment without backend calls',
    () async {
      ConnectivityService.testIsOnline = () async => false;
      var incrementCalls = 0;
      var undoCalls = 0;
      GroupCounterApiService.testIncrementMyGroupCounter =
          (groupId, amount) async {
            incrementCalls += 1;
            return CounterIncrementResult(
              count: amount,
              incrementRequestId: 1,
              undoExpiresAt: undoExpiresAt,
            );
          };
      GroupCounterApiService.testUndoCounterIncrement =
          (groupId, incrementRequestId) async {
            undoCalls += 1;
            return CounterUndoResult(
              count: 0,
              incrementRequestId: incrementRequestId,
              undoneAt: DateTime.now().toUtc(),
            );
          };

      await OfflineStrichService.saveLastOnlineCounter(userEmail, groupId, 0);
      final operation =
          await OfflineStrichService.addPendingOwnCounterIncrement(
            userEmail,
            groupId,
            1,
          );

      final undoResult = await OfflineStrichService.undoOwnCounterIncrement(
        userEmail,
        groupId,
        operation.id,
        1,
        isSyncing: false,
      );

      expect(undoResult.count, 0);
      expect(undoResult.hasPendingSync, isFalse);
      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
      expect(
        await OfflineStrichService.getConfirmedIncrement(
          userEmail,
          operation.id,
          groupId: groupId,
        ),
        isNull,
      );
      expect(incrementCalls, 0);
      expect(undoCalls, 0);
    },
  );

  test(
    'own-counter sync keeps undo queued during in-flight increment and syncs it afterwards',
    () async {
      ConnectivityService.testIsOnline = () async => true;
      final incrementStarted = Completer<void>();
      final releaseIncrement = Completer<void>();
      final undoRequestIds = <int>[];

      GroupCounterApiService.testIncrementMyGroupCounter =
          (groupId, amount) async {
            if (!incrementStarted.isCompleted) {
              incrementStarted.complete();
            }
            await releaseIncrement.future;
            return CounterIncrementResult(
              count: amount,
              incrementRequestId: 123,
              undoExpiresAt: undoExpiresAt,
            );
          };
      GroupCounterApiService.testUndoCounterIncrement =
          (groupId, incrementRequestId) async {
            undoRequestIds.add(incrementRequestId);
            return CounterUndoResult(
              count: 0,
              incrementRequestId: incrementRequestId,
              undoneAt: DateTime.now().toUtc(),
            );
          };

      await OfflineStrichService.saveLastOnlineCounter(userEmail, groupId, 0);
      final operation =
          await OfflineStrichService.addPendingOwnCounterIncrement(
            userEmail,
            groupId,
            1,
          );

      final firstSync = OfflineStrichService.syncPendingOperations(userEmail);
      await incrementStarted.future;

      final undoResult = await OfflineStrichService.undoOwnCounterIncrement(
        userEmail,
        groupId,
        operation.id,
        1,
        isSyncing: true,
      );

      expect(undoResult.hasPendingSync, isTrue);
      expect(undoResult.count, 0);

      releaseIncrement.complete();
      expect(await firstSync, isTrue);

      final queuedAfterFirstSync = await PendingSyncQueueService.getOperations(
        userEmail,
      );
      expect(
        queuedAfterFirstSync.map((entry) => entry.operationType),
        contains(PendingSyncOperation.undoOwnCounterIncrement),
      );

      expect(
        await OfflineStrichService.syncPendingOperations(userEmail),
        isTrue,
      );
      expect(undoRequestIds, [123]);
      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
      expect(
        await OfflineStrichService.getConfirmedIncrement(
          userEmail,
          operation.id,
          groupId: groupId,
        ),
        isNull,
      );
      expect(
        await OfflineStrichService.getLastOnlineCounter(userEmail, groupId),
        0,
      );
    },
  );

  test(
    'own-counter retry path drops local increment plus queued undo without backend undo call',
    () async {
      ConnectivityService.testIsOnline = () async => true;
      final incrementStarted = Completer<void>();
      final releaseIncrement = Completer<void>();
      var undoCalls = 0;

      GroupCounterApiService.testIncrementMyGroupCounter =
          (groupId, amount) async {
            if (!incrementStarted.isCompleted) {
              incrementStarted.complete();
            }
            await releaseIncrement.future;
            throw GroupCounterApiException('Netzwerkfehler');
          };
      GroupCounterApiService.testUndoCounterIncrement =
          (groupId, incrementRequestId) async {
            undoCalls += 1;
            return CounterUndoResult(
              count: 0,
              incrementRequestId: incrementRequestId,
              undoneAt: DateTime.now().toUtc(),
            );
          };

      await OfflineStrichService.saveLastOnlineCounter(userEmail, groupId, 0);
      final operation =
          await OfflineStrichService.addPendingOwnCounterIncrement(
            userEmail,
            groupId,
            1,
          );

      final firstSync = OfflineStrichService.syncPendingOperations(userEmail);
      await incrementStarted.future;

      final undoResult = await OfflineStrichService.undoOwnCounterIncrement(
        userEmail,
        groupId,
        operation.id,
        1,
        isSyncing: true,
      );

      expect(undoResult.hasPendingSync, isTrue);
      releaseIncrement.complete();
      expect(await firstSync, isFalse);

      final queuedAfterFailure = await PendingSyncQueueService.getOperations(
        userEmail,
      );
      expect(queuedAfterFailure.map((entry) => entry.operationType).toSet(), {
        PendingSyncOperation.incrementOwnCounter,
        PendingSyncOperation.undoOwnCounterIncrement,
      });

      expect(
        await OfflineStrichService.syncPendingOperations(userEmail),
        isTrue,
      );
      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
      expect(undoCalls, 0);
      expect(
        await OfflineStrichService.getConfirmedIncrement(
          userEmail,
          operation.id,
          groupId: groupId,
        ),
        isNull,
      );
    },
  );

  test('offline member settlement preserves negative balances', () async {
    ConnectivityService.testIsOnline = () async => false;
    const member = GroupMember(
      userId: targetUserId,
      username: 'Mia',
      strichCount: 1,
      role: GroupMemberRole.member,
    );

    await OfflineGroupUsersService.saveGroupMembers(userEmail, groupId, [
      member,
    ]);

    final result = await OfflineGroupUsersService.settleMemberStriche(
      userEmail,
      groupId,
      member,
      3,
      affectsCurrentUser: false,
    );

    expect(result.hasPendingSync, isTrue);
    expect(result.members.single.strichCount, -2);

    final cachedMembers = await OfflineGroupUsersService.getGroupMembers(
      userEmail,
      groupId,
    );
    expect(cachedMembers, isNotNull);
    expect(cachedMembers!.single.strichCount, -2);
  });

  test(
    'member-counter sync keeps undo queued during in-flight increment and syncs it afterwards',
    () async {
      ConnectivityService.testIsOnline = () async => false;
      final incrementStarted = Completer<void>();
      final releaseIncrement = Completer<void>();
      final undoRequestIds = <int>[];
      const member = GroupMember(
        userId: targetUserId,
        username: 'Mia',
        strichCount: 0,
        role: GroupMemberRole.member,
      );

      await OfflineGroupUsersService.saveGroupMembers(userEmail, groupId, [
        member,
      ]);

      final queuedIncrement =
          await OfflineGroupUsersService.incrementMemberCounter(
            userEmail,
            groupId,
            member,
            1,
            affectsCurrentUser: false,
          );

      expect(queuedIncrement.hasPendingSync, isTrue);
      expect(queuedIncrement.localOperationId, isNotNull);

      ConnectivityService.testIsOnline = () async => true;
      GroupApiService.testFetchGroupMembers = (groupId) async => const [
        GroupMember(
          userId: targetUserId,
          username: 'Mia',
          strichCount: 1,
          role: GroupMemberRole.member,
        ),
      ];
      GroupCounterApiService.testIncrementGroupMemberCounter =
          (groupId, targetUserId, amount) async {
            if (!incrementStarted.isCompleted) {
              incrementStarted.complete();
            }
            await releaseIncrement.future;
            return CounterIncrementResult(
              count: amount,
              incrementRequestId: 456,
              undoExpiresAt: undoExpiresAt,
            );
          };
      GroupCounterApiService.testUndoCounterIncrement =
          (groupId, incrementRequestId) async {
            undoRequestIds.add(incrementRequestId);
            return CounterUndoResult(
              count: 0,
              incrementRequestId: incrementRequestId,
              undoneAt: DateTime.now().toUtc(),
            );
          };

      final firstSync = OfflineGroupUsersService.syncPendingOperations(
        userEmail,
      );
      await incrementStarted.future;

      final undoResult =
          await OfflineGroupUsersService.undoMemberCounterIncrement(
            userEmail,
            groupId,
            member,
            queuedIncrement.localOperationId!,
            1,
            affectsCurrentUser: false,
            isSyncing: true,
          );

      expect(undoResult.hasPendingSync, isTrue);
      expect(undoResult.members.single.strichCount, 0);

      releaseIncrement.complete();
      expect(await firstSync, isTrue);
      expect(
        await OfflineGroupUsersService.syncPendingOperations(userEmail),
        isTrue,
      );

      final finalMembers = await OfflineGroupUsersService.getGroupMembers(
        userEmail,
        groupId,
      );
      expect(finalMembers, isNotNull);
      expect(finalMembers!.single.strichCount, 0);
      expect(undoRequestIds, [456]);
      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
    },
  );

  test(
    'global pending sync processes member increment and queued undo across two cycles',
    () async {
      ConnectivityService.testIsOnline = () async => false;
      final incrementStarted = Completer<void>();
      final releaseIncrement = Completer<void>();
      final undoRequestIds = <int>[];
      const member = GroupMember(
        userId: targetUserId,
        username: 'Mia',
        strichCount: 0,
        role: GroupMemberRole.member,
      );

      await OfflineGroupUsersService.saveGroupMembers(userEmail, groupId, [
        member,
      ]);

      final queuedIncrement =
          await OfflineGroupUsersService.incrementMemberCounter(
            userEmail,
            groupId,
            member,
            1,
            affectsCurrentUser: false,
          );

      ConnectivityService.testIsOnline = () async => true;
      GroupApiService.testFetchGroupMembers = (groupId) async => const [
        GroupMember(
          userId: targetUserId,
          username: 'Mia',
          strichCount: 1,
          role: GroupMemberRole.member,
        ),
      ];
      GroupCounterApiService.testIncrementGroupMemberCounter =
          (groupId, targetUserId, amount) async {
            if (!incrementStarted.isCompleted) {
              incrementStarted.complete();
            }
            await releaseIncrement.future;
            return CounterIncrementResult(
              count: amount,
              incrementRequestId: 789,
              undoExpiresAt: undoExpiresAt,
            );
          };
      GroupCounterApiService.testUndoCounterIncrement =
          (groupId, incrementRequestId) async {
            undoRequestIds.add(incrementRequestId);
            return CounterUndoResult(
              count: 0,
              incrementRequestId: incrementRequestId,
              undoneAt: DateTime.now().toUtc(),
            );
          };

      final firstSync = PendingSyncService.syncPendingOperations(userEmail);
      await incrementStarted.future;

      final undoResult =
          await OfflineGroupUsersService.undoMemberCounterIncrement(
            userEmail,
            groupId,
            member,
            queuedIncrement.localOperationId!,
            1,
            affectsCurrentUser: false,
            isSyncing: true,
          );

      expect(undoResult.hasPendingSync, isTrue);
      expect(undoResult.members.single.strichCount, 0);

      releaseIncrement.complete();
      expect(await firstSync, isTrue);
      expect(await PendingSyncService.syncPendingOperations(userEmail), isTrue);
      expect(undoRequestIds, [789]);
      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
    },
  );

  test(
    'member sync still succeeds when refresh fails after successful increment and pending undo remains',
    () async {
      ConnectivityService.testIsOnline = () async => false;
      final incrementStarted = Completer<void>();
      final releaseIncrement = Completer<void>();
      final undoRequestIds = <int>[];
      var fetchGroupMembersCalls = 0;
      const member = GroupMember(
        userId: targetUserId,
        username: 'Mia',
        strichCount: 0,
        role: GroupMemberRole.member,
      );

      await OfflineGroupUsersService.saveGroupMembers(userEmail, groupId, [
        member,
      ]);

      final queuedIncrement =
          await OfflineGroupUsersService.incrementMemberCounter(
            userEmail,
            groupId,
            member,
            1,
            affectsCurrentUser: false,
          );

      ConnectivityService.testIsOnline = () async => true;
      GroupApiService.testFetchGroupMembers = (groupId) async {
        fetchGroupMembersCalls += 1;
        throw GroupApiException('Netzwerkfehler');
      };
      GroupCounterApiService.testIncrementGroupMemberCounter =
          (groupId, targetUserId, amount) async {
            if (!incrementStarted.isCompleted) {
              incrementStarted.complete();
            }
            await releaseIncrement.future;
            return CounterIncrementResult(
              count: amount,
              incrementRequestId: 654,
              undoExpiresAt: undoExpiresAt,
            );
          };
      GroupCounterApiService.testUndoCounterIncrement =
          (groupId, incrementRequestId) async {
            undoRequestIds.add(incrementRequestId);
            return CounterUndoResult(
              count: 0,
              incrementRequestId: incrementRequestId,
              undoneAt: DateTime.now().toUtc(),
            );
          };

      final firstSync = OfflineGroupUsersService.syncPendingOperations(
        userEmail,
      );
      await incrementStarted.future;

      await OfflineGroupUsersService.undoMemberCounterIncrement(
        userEmail,
        groupId,
        member,
        queuedIncrement.localOperationId!,
        1,
        affectsCurrentUser: false,
        isSyncing: true,
      );

      releaseIncrement.complete();
      expect(await firstSync, isTrue);
      expect(fetchGroupMembersCalls, 1);

      final cachedMembers = await OfflineGroupUsersService.getGroupMembers(
        userEmail,
        groupId,
      );
      expect(cachedMembers, isNotNull);
      expect(cachedMembers!.single.strichCount, 0);

      expect(
        await OfflineGroupUsersService.syncPendingOperations(userEmail),
        isTrue,
      );
      expect(undoRequestIds, [654]);
      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
    },
  );

  test(
    'sync provider skips execution when only delayed retry operations remain',
    () async {
      ConnectivityService.testIsOnline = () async => true;
      TokenService.testGetUserEmail = () async => userEmail;

      final delayedOperation = PendingSyncOperation(
        id: 'delayed-op',
        userEmail: userEmail,
        domain: PendingSyncOperation.domainGroupUsers,
        operationType: PendingSyncOperation.undoGroupMemberCounterIncrement,
        groupId: groupId,
        payload: const {
          'localOperationId': 'local-op',
          'targetUserId': targetUserId,
          'amount': 1,
          'localStrichDelta': -1,
        },
        createdAt: DateTime.now().toUtc(),
        retryCount: 1,
        nextAttemptAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
      await PendingSyncQueueService.addOperation(delayedOperation);

      final syncProvider = SyncProvider();
      addTearDown(syncProvider.dispose);

      var syncCalls = 0;
      syncProvider.registerSyncHandler(() async {
        syncCalls += 1;
        return true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(syncProvider.hasPendingSync, isTrue);
      expect(syncProvider.isSyncing, isFalse);
      expect(syncCalls, 0);
    },
  );

  test(
    'undo retries are scheduled aggressively within the undo window',
    () async {
      final now = DateTime.now().toUtc();
      final operation = PendingSyncOperation(
        id: 'undo-op',
        userEmail: userEmail,
        domain: PendingSyncOperation.domainGroupUsers,
        operationType: PendingSyncOperation.undoGroupMemberCounterIncrement,
        groupId: groupId,
        payload: const {'localOperationId': 'local-op'},
        createdAt: now,
      );

      final updated = PendingSyncQueueService.scheduleUndoRetry(
        operation,
        now.add(const Duration(seconds: 30)),
      );

      expect(updated.retryCount, 1);
      expect(updated.nextAttemptAt, isNotNull);
      expect(
        updated.nextAttemptAt!.difference(now).inSeconds,
        lessThanOrEqualTo(2),
      );
    },
  );

  test(
    'replaceOperation does not recreate an already removed queue entry',
    () async {
      final operation = PendingSyncQueueService.createOperation(
        userEmail: userEmail,
        domain: PendingSyncOperation.domainCounter,
        operationType: PendingSyncOperation.incrementOwnCounter,
        groupId: groupId,
        payload: const {'amount': 1},
      );
      await PendingSyncQueueService.addOperation(operation);
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);

      await PendingSyncQueueService.replaceOperation(
        userEmail,
        PendingSyncQueueService.scheduleRetry(operation),
      );

      expect(await PendingSyncQueueService.getOperations(userEmail), isEmpty);
    },
  );
}

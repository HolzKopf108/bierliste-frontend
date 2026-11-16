import 'dart:async';
import 'dart:io';

import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/models/group_counter.dart';
import 'package:bierliste/providers/sync_provider.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_counter_api_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/offline_strich_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:bierliste/services/sync_debug_service.dart';
import 'package:bierliste/widgets/sync_status_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const email = 'sync@example.com';
  late Directory directory;

  Future<PendingSyncOperation> increment([int group = 1, int amount = 1]) =>
      OfflineStrichService.addPendingOwnCounterIncrement(email, group, amount);

  Map<String, dynamic> applied(
    PendingSyncOperation operation,
    int count, {
    String status = 'applied',
  }) => {
    'clientEventId': operation.clientEventId,
    'status': status,
    'statusCode': 200,
    'serverStateDelta': {
      'groupId': operation.groupId,
      'count': count,
      'incrementRequestId': 123,
      'undoExpiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
    },
  };

  Future<void> makeReady() async {
    final operations = await PendingSyncQueueService.getOperations(email);
    await PendingSyncQueueService.saveOperations(
      email,
      operations
          .map(
            (operation) =>
                operation.copyWith(status: 'pending', clearNextAttemptAt: true),
          )
          .toList(),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sync_events_');
    Hive.init(directory.path);
    SyncDebugService.enabled = false;
    ConnectivityService.testIsOnline = () async => false;
    TokenService.testGetUserEmail = () async => email;
  });
  tearDown(() async {
    GroupCounterApiService.testSyncEvents = null;
    GroupCounterApiService.testFetchMyGroupCounter = null;
    ConnectivityService.testIsOnline = null;
    ConnectivityService.testChanges = null;
    TokenService.testGetUserEmail = null;
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('UUID and full event contract survive closing Hive and isolate users/groups', () async {
    final operation = await increment(1, 2);
    await increment(2, 3);
    await PendingSyncQueueService.addOperation(
      PendingSyncQueueService.createOperation(
        userEmail: 'other@example.com',
        domain: PendingSyncOperation.domainCounter,
        operationType: PendingSyncOperation.incrementOwnCounter,
        groupId: 1,
        payload: {'amount': 99},
      ),
    );
    await Hive.close();
    final restored = (await PendingSyncQueueService.getOperations(email)).first;
    expect(restored.clientEventId, operation.clientEventId);
    expect(
      restored.clientEventId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(restored.toClientEvent(), {
      'clientEventId': operation.clientEventId,
      'type': 'INCREMENT_SELF',
      'groupId': 1,
      'payload': {'amount': 2},
      'clientTimestamp': operation.createdAt.toIso8601String(),
    });
    expect(await OfflineStrichService.getEffectiveCounter(email, 1), 2);
    expect(await OfflineStrichService.getEffectiveCounter(email, 2), 3);
    expect(
      await PendingSyncQueueService.getOperations('other@example.com'),
      hasLength(1),
    );
  });

  test('legacy queue receives one durable event ID without changing local undo references', () async {
    final box = await Hive.openBox('pending_sync_queue');
    final legacy = PendingSyncOperation(
      id: 'legacy-id',
      userEmail: email,
      domain: PendingSyncOperation.domainCounter,
      operationType: PendingSyncOperation.incrementOwnCounter,
      groupId: 1,
      payload: {'amount': 1},
      createdAt: DateTime.now().toUtc(),
    ).toJson()..remove('clientEventId');
    await box.put('${email}_pending_sync_operations', [legacy]);
    final first = (await PendingSyncQueueService.getOperations(email)).single;
    await Hive.close();
    final second = (await PendingSyncQueueService.getOperations(email)).single;
    expect(first.id, 'legacy-id');
    expect(second.clientEventId, first.clientEventId);
  });

  test('25 increments use ordered batches of 20 and 5 and acknowledge durable state', () async {
    for (var i = 0; i < 25; i++) {
      await increment();
    }
    final batchSizes = <int>[];
    var count = 0;
    GroupCounterApiService.testSyncEvents = (operations) async {
      batchSizes.add(operations.length);
      return operations
          .map((operation) => applied(operation, ++count))
          .toList();
    };
    expect(await OfflineStrichService.syncPendingOperations(email), isTrue);
    expect(batchSizes, [20, 5]);
    await Hive.close();
    expect(await PendingSyncQueueService.getOperations(email), isEmpty);
    expect(await OfflineStrichService.getEffectiveCounter(email, 1), 25);
  });

  test('server-applied lost response retries same UUID and duplicate does not double count', () async {
    final operation = await increment(1, 2);
    final server = <String>{};
    var count = 0;
    var attempts = 0;
    GroupCounterApiService.testSyncEvents = (operations) async {
      expect(operations.single.clientEventId, operation.clientEventId);
      if (server.add(operations.single.clientEventId!)) count += 2;
      if (++attempts == 1) throw TimeoutException('lost response');
      return [applied(operations.single, count, status: 'duplicate')];
    };
    GroupCounterApiService.testFetchMyGroupCounter = (_) async =>
        GroupCounter(count: count);
    expect(await OfflineStrichService.syncPendingOperations(email), isFalse);
    final queued = (await PendingSyncQueueService.getOperations(email)).single;
    expect(queued.retryCount, 1);
    expect(queued.nextAttemptAt, isNotNull);
    await Hive.close();
    await makeReady();
    expect(await OfflineStrichService.syncPendingOperations(email), isTrue);
    expect(count, 2);
    expect(await OfflineStrichService.getEffectiveCounter(email, 1), 2);
  });

  test('partial failure rolls back optimistic delta and retains terminal problem across restart', () async {
    await increment(1, 2);
    final invalid = await increment(1, 3);
    GroupCounterApiService.testSyncEvents = (operations) async => [
      applied(operations.first, 7),
      {
        'clientEventId': invalid.clientEventId,
        'status': 'failed',
        'statusCode': 404,
        'resolution': 'drop',
        'error': 'Gruppe nicht gefunden',
      },
    ];
    expect(await OfflineStrichService.syncPendingOperations(email), isFalse);
    await Hive.close();
    final failed = (await PendingSyncQueueService.getOperations(email)).single;
    expect(failed.status, 'failed');
    expect(failed.isReadyForSync, isFalse);
    expect(await OfflineStrichService.getEffectiveCounter(email, 1), 7);
    expect(await PendingSyncQueueService.hasPendingOperations(email), isFalse);
  });

  test('duplicate uses current server count and acknowledges a group in one snapshot', () async {
    await OfflineStrichService.saveLastOnlineCounter(email, 1, 10);
    await increment();
    await increment();
    final snapshots = <Future<int>>[];
    final subscription = PendingSyncQueueService.changes.listen((_) {
      snapshots.add(OfflineStrichService.getEffectiveCounter(email, 1));
    });
    GroupCounterApiService.testSyncEvents = (operations) async => [
      applied(operations.first, 11, status: 'duplicate'),
      applied(operations.last, 12, status: 'duplicate'),
    ];
    GroupCounterApiService.testFetchMyGroupCounter = (_) async =>
        const GroupCounter(count: 18);
    expect(await OfflineStrichService.syncPendingOperations(email), isTrue);
    await subscription.cancel();
    expect(await Future.wait(snapshots), everyElement(isIn([12, 18])));
    expect(await OfflineStrichService.getEffectiveCounter(email, 1), 18);
    expect(await PendingSyncQueueService.getOperations(email), isEmpty);
  });

  test(
    'GET during an ambiguous upload cannot double count optimistic increments',
    () async {
      await OfflineStrichService.saveLastOnlineCounter(email, 1, 10);
      final operation = await increment(1, 2);
      await PendingSyncQueueService.replaceOperation(
        email,
        operation.copyWith(status: 'syncing'),
      );
      await OfflineStrichService.saveLastOnlineCounter(
        email,
        1,
        12,
        expectedRevision: PendingSyncQueueService.revision(email),
      );
      expect(await OfflineStrichService.getEffectiveCounter(email, 1), 12);
      await PendingSyncQueueService.recordCounter(
        email,
        1,
        14,
        acknowledgedIds: [operation.id],
      );
      expect(await OfflineStrichService.getEffectiveCounter(email, 1), 14);
    },
  );

  test(
    'uncertain uploads block later events in that group but not other groups',
    () async {
      final first = await increment();
      GroupCounterApiService.testSyncEvents = (_) async =>
          throw TimeoutException('lost');
      expect(await OfflineStrichService.syncPendingOperations(email), isFalse);
      await increment();
      final other = await increment(2);
      GroupCounterApiService.testSyncEvents = (operations) async {
        expect(operations.map((operation) => operation.id), [other.id]);
        return [applied(other, 5)];
      };
      expect(await OfflineStrichService.syncPendingOperations(email), isTrue);
      final pending = await PendingSyncQueueService.getOperations(email);
      expect(pending, hasLength(2));
      expect(pending.first.id, first.id);
    },
  );

  test('retry delay grows exponentially and is capped without a retry-count cutoff', () async {
    var operation = await increment();
    for (final seconds in [15, 30, 60, 120, 240, 480, 480, 480]) {
      final before = DateTime.now().toUtc();
      operation = PendingSyncQueueService.scheduleRetry(operation);
      final delay = operation.nextAttemptAt!.difference(before).inMilliseconds;
      expect(delay, inInclusiveRange(seconds * 1000, seconds * 1000 + 100));
      expect(operation.status, 'pending');
    }
    final restored = PendingSyncOperation.fromJson(operation.toJson());
    expect(restored.toJson(), operation.toJson());
    expect(restored.retryCount, 8);
  });

  for (final statusCode in [400, 403, 404, 409, 429, 500, 503]) {
    test(
      'event failure $statusCode follows terminal versus retry policy',
      () async {
        final operation = await increment();
        GroupCounterApiService.testSyncEvents = (_) async => [
          {
            'clientEventId': operation.clientEventId,
            'status': 'failed',
            'statusCode': statusCode,
            'resolution': statusCode == 429 || statusCode >= 500
                ? 'retry'
                : 'drop',
            'error': 'Aktion konnte nicht synchronisiert werden',
          },
        ];
        expect(
          await OfflineStrichService.syncPendingOperations(email),
          isFalse,
        );
        final queued = (await PendingSyncQueueService.getOperations(email))
            .single;
        final retry = statusCode == 429 || statusCode >= 500;
        expect(queued.status, retry ? 'pending' : 'failed');
        expect(queued.retryCount, retry ? 1 : 0);
        expect(
          await OfflineStrichService.getEffectiveCounter(email, 1),
          retry ? 1 : 0,
        );
      },
    );
  }

  test('a queued user cannot upload under another active account', () async {
    await increment();
    TokenService.testGetUserEmail = () async => 'other@example.com';
    await expectLater(
      OfflineStrichService.syncPendingOperations(email),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(
      (await PendingSyncQueueService.getOperations(email)).single.status,
      'pending',
    );
  });

  test('startup, connectivity and resume trigger serialized sync without background polling', () async {
    final connectivity = StreamController<void>.broadcast(sync: true);
    ConnectivityService.testChanges = connectivity.stream;
    ConnectivityService.testIsOnline = () async => true;
    final started = Completer<void>();
    final release = Completer<void>();
    final resumed = Completer<void>();
    var calls = 0;
    await increment();
    final sync = SyncProvider();
    try {
      sync.registerSyncHandler(() async {
        calls++;
        if (calls == 1) {
          started.complete();
          await release.future;
        }
        if (calls == 2) resumed.complete();
        await PendingSyncQueueService.clearOperations(email);
        return true;
      });
      await started.future.timeout(const Duration(seconds: 5));
      connectivity.add(null);
      final concurrent = sync.requestSync();
      release.complete();
      await concurrent;
      expect(calls, 1);
      sync.didChangeAppLifecycleState(AppLifecycleState.paused);
      await increment();
      connectivity.add(null);
      expect(await sync.requestSync(), isFalse);
      expect(calls, 1);
      sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await resumed.future.timeout(const Duration(seconds: 5));
      await sync.requestSync();
      expect(calls, 2);
      await increment();
      final reconnected = Completer<void>();
      sync.registerSyncHandler(() async {
        calls++;
        await PendingSyncQueueService.clearOperations(email);
        reconnected.complete();
        return true;
      });
      connectivity.add(null);
      await reconnected.future.timeout(const Duration(seconds: 5));
      await sync.requestSync();
      expect(calls, 3);
    } finally {
      sync.dispose();
      await connectivity.close();
    }
  });

  test(
    'malformed partial response acknowledges nothing and preserves all IDs',
    () async {
      final first = await increment();
      final second = await increment();
      GroupCounterApiService.testSyncEvents = (operations) async => [
        applied(operations.first, 1),
      ];
      expect(await OfflineStrichService.syncPendingOperations(email), isFalse);
      final queue = await PendingSyncQueueService.getOperations(email);
      expect(queue.map((operation) => operation.clientEventId), [
        first.clientEventId,
        second.clientEventId,
      ]);
      expect(queue.every((operation) => operation.retryCount == 1), isTrue);
    },
  );

  test(
    'concurrent sync requests preserve events added while batch is in flight',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var uploads = 0;
      var count = 0;
      var active = 0;
      await increment();
      GroupCounterApiService.testSyncEvents = (operations) async {
        expect(++active, 1);
        uploads++;
        if (!started.isCompleted) {
          started.complete();
          await release.future;
        }
        final results = operations
            .map((operation) => applied(operation, ++count))
            .toList();
        active--;
        return results;
      };
      final first = OfflineStrichService.syncPendingOperations(email);
      await started.future;
      await increment();
      final second = OfflineStrichService.syncPendingOperations(email);
      release.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(uploads, 2);
      expect(await OfflineStrichService.getEffectiveCounter(email, 1), 2);
      expect(await PendingSyncQueueService.getOperations(email), isEmpty);
    },
  );

  test(
    'stale GET cannot overwrite state after an acknowledged event',
    () async {
      final operation = await increment();
      final revision = PendingSyncQueueService.revision(email);
      await PendingSyncQueueService.recordCounter(
        email,
        1,
        12,
        acknowledgedIds: [operation.id],
      );
      await OfflineStrichService.saveLastOnlineCounter(
        email,
        1,
        9,
        expectedRevision: revision,
      );
      expect(await OfflineStrichService.getEffectiveCounter(email, 1), 12);
    },
  );

  test('unauthorized upload retains events for the same account', () async {
    final operation = await increment();
    GroupCounterApiService.testSyncEvents = (_) async =>
        throw UnauthorizedException();
    await expectLater(
      OfflineStrichService.syncPendingOperations(email),
      throwsA(isA<UnauthorizedException>()),
    );
    final restored = (await PendingSyncQueueService.getOperations(email))
        .single;
    expect(restored.clientEventId, operation.clientEventId);
    expect(restored.status, 'pending');
  });

  test('expired IDs are not replayed outside backend retention', () async {
    final operation = await increment();
    await PendingSyncQueueService.replaceOperation(
      email,
      operation.copyWith(
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 91)),
      ),
    );
    GroupCounterApiService.testSyncEvents = (_) async =>
        fail('must not upload expired events');
    expect(await OfflineStrichService.syncPendingOperations(email), isFalse);
    expect(
      (await PendingSyncQueueService.getOperations(email)).single.status,
      'failed',
    );
  });

  test(
    'local undo may remove only an increment that is still definitely unsent',
    () async {
      final operation = await increment();
      await PendingSyncQueueService.replaceOperation(
        email,
        operation.copyWith(status: 'syncing'),
      );
      expect(
        await PendingSyncQueueService.removeUnsentCounterIncrement(
          email,
          operation.id,
        ),
        isFalse,
      );
      await PendingSyncQueueService.replaceOperation(
        email,
        operation.copyWith(retryCount: 1),
      );
      expect(
        await PendingSyncQueueService.removeUnsentCounterIncrement(
          email,
          operation.id,
        ),
        isFalse,
      );
      await PendingSyncQueueService.replaceOperation(email, operation);
      expect(
        await PendingSyncQueueService.removeUnsentCounterIncrement(
          email,
          operation.id,
        ),
        isTrue,
      );
      expect(await PendingSyncQueueService.getOperations(email), isEmpty);
    },
  );

  testWidgets(
    'global and group indicators update and terminal failures can be dismissed',
    (tester) async {
      late SyncProvider sync;
      late PendingSyncOperation operation;
      await tester.runAsync(() async {
        sync = SyncProvider();
        operation = await increment();
        await sync.refreshPendingSyncStatus();
      });
      addTearDown(sync.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: sync,
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SyncStatusIndicator(),
                  SyncStatusIndicator(groupId: 1),
                  SyncStatusIndicator(groupId: 2),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Nicht synchronisiert'), findsNWidgets(2));
      await tester.runAsync(
        () => PendingSyncQueueService.replaceOperation(
          email,
          operation.copyWith(status: 'failed', error: 'Gruppe nicht gefunden'),
        ),
      );
      await tester.runAsync(sync.refreshPendingSyncStatus);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Synchronisierung fehlgeschlagen').first);
      await tester.pumpAndSettle();
      expect(find.text('Sync-Probleme'), findsOneWidget);
      expect(find.text('Gruppe nicht gefunden'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Hinweis verwerfen'));
        await sync.refreshPendingSyncStatus();
      });
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => PendingSyncQueueService.getOperations(email),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

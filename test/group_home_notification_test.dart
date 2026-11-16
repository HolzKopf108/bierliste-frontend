import 'dart:io';

import 'package:bierliste/models/group_counter.dart';
import 'package:bierliste/models/group_member_notification.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/group_role_provider.dart';
import 'package:bierliste/providers/sync_provider.dart';
import 'package:bierliste/screens/group_home_page.dart';
import 'package:bierliste/services/android_notification_service.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_counter_api_service.dart';
import 'package:bierliste/services/group_notification_api_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  Future<void> resetTestState() async {
    ConnectivityService.testIsOnline = null;
    ConnectivityService.testIsDeviceOnline = null;
    ConnectivityService.testIsServerOnline = null;
    GroupCounterApiService.testFetchMyGroupCounter = null;
    GroupNotificationApiService.testFetchMyNotifications = null;
    GroupNotificationApiService.testConfirmNotification = null;
    SharedPreferences.setMockInitialValues({});
    await Hive.close();
  }

  setUp(() async {
    await resetTestState();
    tempDir = await Directory.systemTemp.createTemp(
      'bierliste_group_home_notification_',
    );
    Hive.init(tempDir!.path);
  });

  Future<void> pumpUntilNotFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isEmpty) {
        return;
      }
    }

    fail('Widget still found after timeout: $finder');
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }

    fail('Widget not found within timeout: $finder');
  }

  Future<void> pumpPage(WidgetTester tester, Widget widget) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  tearDown(() async {
    await resetTestState();
    final directory = tempDir;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    tempDir = null;
  });

  testWidgets('group home shows open notifications and confirms one entry', (
    tester,
  ) async {
    ConnectivityService.testIsOnline = () async => false;
    GroupCounterApiService.testFetchMyGroupCounter = (groupId) async =>
        const GroupCounter(count: 2);

    final confirmedNotificationIds = <int>{};
    var confirmCalls = 0;
    final olderNotification = GroupMemberNotification(
      id: 9,
      groupId: 5,
      actorUserId: 2,
      actorUsername: 'Alex',
      targetUserId: 7,
      message: 'Bring heute 3,50€ mit',
      createdAt: DateTime.parse('2026-03-27T12:00:00Z'),
    );
    final newerNotification = GroupMemberNotification(
      id: 10,
      groupId: 5,
      actorUserId: 3,
      actorUsername: 'Chris',
      targetUserId: 7,
      message: 'Bring heute 7,00€ mit',
      createdAt: DateTime.parse('2026-03-27T12:15:00Z'),
    );

    GroupNotificationApiService.testFetchMyNotifications = (groupId) async {
      return [olderNotification, newerNotification].where((notification) {
        return !confirmedNotificationIds.contains(notification.id);
      }).toList();
    };
    GroupNotificationApiService.testConfirmNotification =
        (groupId, notificationId) async {
          confirmCalls += 1;
          confirmedNotificationIds.add(notificationId);
          return GroupMemberNotification(
            id: notificationId,
            groupId: groupId,
            actorUserId: 2,
            actorUsername: 'Alex',
            targetUserId: 7,
            message: 'Bring heute 3,50€ mit',
            createdAt: DateTime.parse('2026-03-27T12:00:00Z'),
            confirmedAt: DateTime.parse('2026-03-27T12:05:00Z'),
          );
        };

    await pumpPage(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: TestAuthProvider(userEmail: 'max@example.com'),
          ),
          ChangeNotifierProvider<GroupRoleProvider>.value(
            value: TestGroupRoleProvider(),
          ),
          ChangeNotifierProvider<SyncProvider>.value(value: TestSyncProvider()),
        ],
        child: const MaterialApp(
          home: GroupHomePage(groupId: 5, groupName: 'Bierfreunde'),
        ),
      ),
    );

    expect(
      find.byKey(const Key('pendingGroupNotificationSection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pendingGroupNotificationCard_9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pendingGroupNotificationCard_10')),
      findsOneWidget,
    );
    expect(find.text('Bring heute 3,50€ mit'), findsOneWidget);
    expect(find.text('Bring heute 7,00€ mit'), findsOneWidget);
    expect(
      find.byKey(const Key('confirmGroupNotificationButton_10')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('confirmGroupNotificationButton_10')),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await pumpUntilNotFound(
      tester,
      find.byKey(const Key('pendingGroupNotificationCard_10')),
    );

    expect(confirmCalls, 1);
    expect(
      find.byKey(const Key('pendingGroupNotificationCard_10')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('pendingGroupNotificationCard_9')),
      findsOneWidget,
    );
    expect(find.text('Bring heute 7,00€ mit'), findsNothing);
    expect(find.text('Bring heute 3,50€ mit'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'group home refreshes open notifications when matching push arrives in-app',
    (tester) async {
      ConnectivityService.testIsOnline = () async => false;
      GroupCounterApiService.testFetchMyGroupCounter = (groupId) async =>
          const GroupCounter(count: 2);

      var notifications = <GroupMemberNotification>[];
      GroupNotificationApiService.testFetchMyNotifications = (groupId) async =>
          notifications;

      await pumpPage(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: TestAuthProvider(userEmail: 'max@example.com'),
            ),
            ChangeNotifierProvider<GroupRoleProvider>.value(
              value: TestGroupRoleProvider(),
            ),
            ChangeNotifierProvider<SyncProvider>.value(
              value: TestSyncProvider(),
            ),
          ],
          child: const MaterialApp(
            home: GroupHomePage(groupId: 5, groupName: 'Bierfreunde'),
          ),
        ),
      );

      expect(
        find.byKey(const Key('pendingGroupNotificationSection')),
        findsNothing,
      );

      notifications = [
        GroupMemberNotification(
          id: 11,
          groupId: 5,
          actorUserId: 3,
          actorUsername: 'Chris',
          targetUserId: 7,
          message: 'Bring heute 5,00€ mit',
          createdAt: DateTime.parse('2026-03-27T12:25:00Z'),
        ),
      ];

      AndroidNotificationService.instance
          .debugDispatchIncomingGroupNotification(5);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.byKey(const Key('pendingGroupNotificationCard_11')),
      );

      expect(find.text('Bring heute 5,00€ mit'), findsOneWidget);
    },
  );
}

class TestAuthProvider extends AuthProvider {
  TestAuthProvider({required String? userEmail}) : _testUserEmail = userEmail;

  final String? _testUserEmail;

  @override
  bool get isAuthenticated => true;

  @override
  String? get userEmail => _testUserEmail;
}

class TestGroupRoleProvider extends GroupRoleProvider {
  @override
  Future<void> loadRole(
    String userEmail,
    int groupId, {
    bool forceRefresh = false,
  }) async {}
}

class TestSyncProvider extends SyncProvider {
  @override
  void initialize() {}

  @override
  bool get isAppOnline => false;

  @override
  bool get isSyncing => false;

  @override
  bool get hasPendingSync => false;
}

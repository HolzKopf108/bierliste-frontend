import 'dart:io';

import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/user.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/group_role_provider.dart';
import 'package:bierliste/providers/sync_provider.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:bierliste/screens/group_users_page.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/offline_group_users_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  Future<void> resetTestState() async {
    ConnectivityService.testIsOnline = null;
    ConnectivityService.testIsDeviceOnline = null;
    ConnectivityService.testIsServerOnline = null;
    GroupApiService.testFetchGroupMembers = null;
    await Hive.close();
  }

  setUp(() async {
    await resetTestState();
    tempDir = await Directory.systemTemp.createTemp(
      'bierliste_group_users_notifications_',
    );
    Hive.init(tempDir!.path);
  });

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

  Future<void> saveMembers(WidgetTester tester, List<GroupMember> members) {
    return tester.runAsync(() async {
      await OfflineGroupUsersService.saveGroupMembers(
        'max@example.com',
        5,
        members,
      );
    });
  }

  tearDown(() async {
    await resetTestState();
    final directory = tempDir;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    tempDir = null;
  });

  testWidgets('wart sees reminder status and can open send dialog from menu', (
    tester,
  ) async {
    ConnectivityService.testIsOnline = () async => false;
    final members = [
      GroupMember(
        userId: 1,
        username: 'Max',
        strichCount: 0,
        role: GroupMemberRole.wart,
        outstandingAmount: 0,
        canReceiveNotification: true,
        hasPendingNotification: false,
        lastNotificationSentAt: DateTime.parse('2026-03-25T08:00:00Z'),
        lastNotificationConfirmedAt: DateTime.parse('2026-03-25T08:30:00Z'),
      ),
      GroupMember(
        userId: 2,
        username: 'Mia',
        strichCount: 4,
        role: GroupMemberRole.member,
        outstandingAmount: 3.5,
        canReceiveNotification: true,
        hasPendingNotification: true,
        lastNotificationSentAt: DateTime.parse('2026-03-27T11:45:00Z'),
      ),
      GroupMember(
        userId: 3,
        username: 'Ben',
        strichCount: 1,
        role: GroupMemberRole.member,
        outstandingAmount: 1.2,
        canReceiveNotification: false,
        hasPendingNotification: false,
        lastNotificationSentAt: DateTime.parse('2026-03-26T09:15:00Z'),
        lastNotificationConfirmedAt: DateTime.parse('2026-03-26T10:05:00Z'),
      ),
    ];

    await saveMembers(tester, members);

    await pumpPage(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: TestAuthProvider(userEmail: 'max@example.com'),
          ),
          ChangeNotifierProvider<UserProvider>.value(
            value: TestUserProvider(
              User(
                email: 'max@example.com',
                username: 'Max',
                lastUpdated: DateTime.utc(2026, 3, 27),
                googleUser: false,
                userId: 1,
              ),
            ),
          ),
          ChangeNotifierProvider<GroupRoleProvider>.value(
            value: TestGroupRoleProvider(role: GroupMemberRole.wart),
          ),
          ChangeNotifierProvider<SyncProvider>.value(value: TestSyncProvider()),
        ],
        child: const MaterialApp(
          home: GroupUsersPage(groupId: 5, groupName: 'Bierfreunde'),
        ),
      ),
    );

    expect(find.text('3,50 €'), findsOneWidget);
    expect(find.byKey(const Key('memberNotificationStatus_1')), findsOneWidget);
    expect(find.byKey(const Key('memberNotificationStatus_2')), findsOneWidget);
    expect(find.textContaining('offen'), findsOneWidget);
    expect(find.byKey(const Key('memberNotificationStatus_3')), findsOneWidget);
    expect(find.textContaining('bestätigt'), findsNWidgets(2));

    expect(find.byKey(const Key('memberOwnIconHighlight_1')), findsOneWidget);
    expect(find.byKey(const Key('memberOwnIconHighlight_2')), findsNothing);
    expect(
      find.byKey(const Key('memberOwnUsernameHighlight_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('memberOwnUsernameHighlight_2')), findsNothing);

    await tester.tap(find.byKey(const Key('memberActionsMenu_3')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('memberNotificationMenuAction_3')),
      findsNothing,
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('memberActionsMenu_2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('memberNotificationMenuAction_2')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('memberNotificationMenuAction_2')));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('sendGroupNotificationMessageField')),
    );

    expect(
      find.byKey(const Key('sendGroupNotificationMessageField')),
      findsOneWidget,
    );
    expect(find.text('Bring heute 3,50€ mit'), findsOneWidget);
  });

  testWidgets(
    'normal member does not see notification details in member overview',
    (tester) async {
      ConnectivityService.testIsOnline = () async => false;
      final members = [
        GroupMember(
          userId: 2,
          username: 'Mia',
          strichCount: 4,
          role: GroupMemberRole.member,
          outstandingAmount: 3.5,
          canReceiveNotification: true,
          hasPendingNotification: true,
          lastNotificationSentAt: DateTime.parse('2026-03-27T11:45:00Z'),
        ),
      ];

      await saveMembers(tester, members);

      await pumpPage(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: TestAuthProvider(userEmail: 'max@example.com'),
            ),
            ChangeNotifierProvider<UserProvider>.value(
              value: TestUserProvider(
                User(
                  email: 'max@example.com',
                  username: 'Max',
                  lastUpdated: DateTime.utc(2026, 3, 27),
                  googleUser: false,
                  userId: 99,
                ),
              ),
            ),
            ChangeNotifierProvider<GroupRoleProvider>.value(
              value: TestGroupRoleProvider(role: GroupMemberRole.member),
            ),
            ChangeNotifierProvider<SyncProvider>.value(
              value: TestSyncProvider(),
            ),
          ],
          child: const MaterialApp(
            home: GroupUsersPage(groupId: 5, groupName: 'Bierfreunde'),
          ),
        ),
      );

      expect(find.byKey(const Key('memberNotificationStatus_2')), findsNothing);
      expect(find.textContaining('offen'), findsNothing);
      expect(find.textContaining('bestätigt'), findsNothing);
      expect(find.byKey(const Key('memberOwnIconHighlight_2')), findsNothing);
      expect(
        find.byKey(const Key('memberOwnUsernameHighlight_2')),
        findsNothing,
      );
    },
  );

  testWidgets('own highlight depends on userId and not on matching username', (
    tester,
  ) async {
    ConnectivityService.testIsOnline = () async => false;
    final members = [
      GroupMember(
        userId: 2,
        username: 'Max',
        strichCount: 1,
        role: GroupMemberRole.member,
      ),
    ];

    await saveMembers(tester, members);

    await pumpPage(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: TestAuthProvider(userEmail: 'max@example.com'),
          ),
          ChangeNotifierProvider<UserProvider>.value(
            value: TestUserProvider(
              User(
                email: 'max@example.com',
                username: 'Max',
                lastUpdated: DateTime.utc(2026, 3, 27),
                googleUser: false,
                userId: 99,
              ),
            ),
          ),
          ChangeNotifierProvider<GroupRoleProvider>.value(
            value: TestGroupRoleProvider(role: GroupMemberRole.wart),
          ),
          ChangeNotifierProvider<SyncProvider>.value(value: TestSyncProvider()),
        ],
        child: const MaterialApp(
          home: GroupUsersPage(groupId: 5, groupName: 'Bierfreunde'),
        ),
      ),
    );

    expect(find.byKey(const Key('memberOwnIconHighlight_2')), findsNothing);
    expect(find.byKey(const Key('memberOwnUsernameHighlight_2')), findsNothing);
  });
}

class TestAuthProvider extends AuthProvider {
  TestAuthProvider({required String? userEmail}) : _testUserEmail = userEmail;

  final String? _testUserEmail;

  @override
  bool get isAuthenticated => true;

  @override
  String? get userEmail => _testUserEmail;
}

class TestUserProvider extends UserProvider {
  TestUserProvider(this.testUser);

  final User? testUser;

  @override
  User? get user => testUser;
}

class TestGroupRoleProvider extends GroupRoleProvider {
  TestGroupRoleProvider({required this.role});

  final GroupMemberRole role;

  @override
  GroupMemberRole? roleForGroup(int groupId) => role;

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

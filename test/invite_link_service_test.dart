import 'package:bierliste/models/group.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/group_role_provider.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/invite_link_service.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestAuthProvider authProvider;
  late FakeGroupApiService groupApiService;
  late InviteLinkService inviteLinkService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authProvider = TestAuthProvider();
    groupApiService = FakeGroupApiService();
    inviteLinkService = InviteLinkService(groupApiService: groupApiService);
  });

  Future<BuildContext> pumpHarness(WidgetTester tester) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => GroupRoleProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    return capturedContext;
  }

  testWidgets('logged in users trigger invite join api', (tester) async {
    final context = await pumpHarness(tester);
    await inviteLinkService.storePendingInviteToken('join-token');
    authProvider.setAuthenticated('alex@example.com');

    Group? joinedGroup;
    final result = await inviteLinkService.handlePendingInviteIfPossible(
      context: context,
      onJoinSuccess: (group) async {
        joinedGroup = group;
      },
    );

    expect(result, isTrue);
    expect(groupApiService.joinCallCount, 1);
    expect(groupApiService.lastJoinToken, 'join-token');
    expect(joinedGroup?.id, 42);
  });

  testWidgets('pending invite continues after login', (tester) async {
    final context = await pumpHarness(tester);
    await inviteLinkService.storePendingInviteToken('pending-after-login');

    final firstResult = await inviteLinkService.handlePendingInviteIfPossible(
      context: context,
      onJoinSuccess: (_) async {},
    );

    expect(firstResult, isFalse);
    expect(groupApiService.joinCallCount, 0);

    authProvider.setAuthenticated('maria@example.com');

    final secondResult = await inviteLinkService.handlePendingInviteIfPossible(
      context: context,
      onJoinSuccess: (_) async {},
    );

    expect(secondResult, isTrue);
    expect(groupApiService.joinCallCount, 1);
    expect(groupApiService.lastJoinToken, 'pending-after-login');
  });

  testWidgets('404 join error is mapped cleanly', (tester) async {
    final context = await pumpHarness(tester);
    await inviteLinkService.storePendingInviteToken('missing-token');
    authProvider.setAuthenticated('alex@example.com');
    groupApiService.joinError = GroupApiException('Not found', statusCode: 404);

    String? feedbackMessage;
    ToastType? feedbackType;
    final result = await inviteLinkService.handlePendingInviteIfPossible(
      context: context,
      onMessage: (message, {type = ToastType.error}) {
        feedbackMessage = message;
        feedbackType = type;
      },
    );

    expect(result, isFalse);
    expect(feedbackMessage, 'Einladung ungültig');
    expect(feedbackType, ToastType.warning);
  });

  testWidgets('410 join error is mapped cleanly', (tester) async {
    final context = await pumpHarness(tester);
    await inviteLinkService.storePendingInviteToken('expired-token');
    authProvider.setAuthenticated('alex@example.com');
    groupApiService.joinError = GroupApiException('Expired', statusCode: 410);

    String? feedbackMessage;
    final result = await inviteLinkService.handlePendingInviteIfPossible(
      context: context,
      onMessage: (message, {type = ToastType.error}) {
        feedbackMessage = message;
      },
    );

    expect(result, isFalse);
    expect(feedbackMessage, 'Einladung abgelaufen');
  });

  testWidgets('network join error is mapped cleanly', (tester) async {
    final context = await pumpHarness(tester);
    await inviteLinkService.storePendingInviteToken('offline-token');
    authProvider.setAuthenticated('alex@example.com');
    groupApiService.joinError = GroupApiException('Netzwerkfehler');

    String? feedbackMessage;
    final result = await inviteLinkService.handlePendingInviteIfPossible(
      context: context,
      onMessage: (message, {type = ToastType.error}) {
        feedbackMessage = message;
      },
    );

    expect(result, isFalse);
    expect(feedbackMessage, 'Keine Verbindung. Bitte Link erneut öffnen.');
  });
}

class FakeGroupApiService extends GroupApiService {
  int joinCallCount = 0;
  String? lastJoinToken;
  GroupApiException? joinError;

  @override
  Future<Group> joinGroupByInviteToken(String token) async {
    joinCallCount += 1;
    lastJoinToken = token;

    final error = joinError;
    if (error != null) {
      throw error;
    }

    return const Group(id: 42, name: 'Testgruppe');
  }
}

class TestAuthProvider extends AuthProvider {
  bool _testAuthenticated = false;
  final bool _testInitialized = true;
  String? _testUserEmail;

  @override
  bool get isAuthenticated => _testAuthenticated;

  @override
  bool get isInitialized => _testInitialized;

  @override
  String? get userEmail => _testUserEmail;

  void setAuthenticated(String userEmail) {
    _testAuthenticated = true;
    _testUserEmail = userEmail;
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> login(
    String accessToken,
    String refreshToken,
    String userEmail,
  ) async {}

  @override
  Future<void> logout({String? reason}) async {}
}

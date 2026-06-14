import 'dart:async';

import 'package:bierliste/models/user.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:bierliste/screens/settings_profil_page.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:bierliste/services/user_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TokenService.testGetUserEmail = null;
    UserApiService.testDeleteAccount = null;
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required TestAuthProvider authProvider,
    required TestUserProvider userProvider,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    TokenService.testGetUserEmail = () async => 'max@example.com';
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: SettingsProfilPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openDeleteFlow(
    WidgetTester tester, {
    required TestAuthProvider authProvider,
    required TestUserProvider userProvider,
  }) async {
    await pumpPage(
      tester,
      authProvider: authProvider,
      userProvider: userProvider,
    );

    final deleteButton = find.text('KONTO LÖSCHEN');
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Finder confirmationField() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Bestätigung',
    );
  }

  Finder dialogActionButton(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
  }

  testWidgets(
    'delete account flow explains anonymization and retries failed requests',
    (tester) async {
      final authProvider = TestAuthProvider();
      final userProvider = TestUserProvider();
      final firstAttempt = Completer<DeleteAccountResult>();
      var callCount = 0;

      UserApiService.testDeleteAccount = () {
        callCount += 1;
        if (callCount == 1) {
          return firstAttempt.future;
        }

        return Future.value(const DeleteAccountResult.success());
      };

      await openDeleteFlow(
        tester,
        authProvider: authProvider,
        userProvider: userProvider,
      );

      expect(find.text('Konto löschen'), findsOneWidget);
      expect(
        find.text(
          'Du wirst aus allen Gruppen entfernt und in den Gruppenverläufen anonymisiert.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Weiter'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Konto endgültig löschen'), findsOneWidget);
      expect(find.text('Konto löschen'), findsOneWidget);

      await tester.enterText(confirmationField(), 'LÖSCHEN');
      await tester.tap(dialogActionButton('Konto löschen'));
      await tester.pump();

      expect(callCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(authProvider.logoutCalls, 0);

      firstAttempt.complete(
        const DeleteAccountResult.failure(
          DeleteAccountFailureType.network,
          'Keine Verbindung. Bitte versuche es erneut.',
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('Keine Verbindung. Bitte versuche es erneut.'),
        findsOneWidget,
      );
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(authProvider.logoutCalls, 0);

      await tester.tap(dialogActionButton('Erneut versuchen'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(callCount, 2);
      expect(authProvider.logoutCalls, 1);
      expect(find.text('Konto endgültig löschen'), findsNothing);
    },
  );

  testWidgets('unauthorized delete failure logs out cleanly', (tester) async {
    final authProvider = TestAuthProvider();
    final userProvider = TestUserProvider();

    UserApiService.testDeleteAccount = () async {
      return const DeleteAccountResult.failure(
        DeleteAccountFailureType.unauthorized,
        'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.',
        statusCode: 401,
      );
    };

    await openDeleteFlow(
      tester,
      authProvider: authProvider,
      userProvider: userProvider,
    );
    await tester.tap(find.text('Weiter'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(confirmationField(), 'LÖSCHEN');
    await tester.tap(dialogActionButton('Konto löschen'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(authProvider.logoutCalls, 1);
    expect(
      authProvider.logoutReasons,
      contains('Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.'),
    );
  });
}

class TestAuthProvider extends AuthProvider {
  int logoutCalls = 0;
  final List<String?> logoutReasons = [];

  @override
  Future<void> logout({String? reason}) async {
    logoutCalls += 1;
    logoutReasons.add(reason);
  }
}

class TestUserProvider extends UserProvider {
  final User _testUser = User(
    email: 'max@example.com',
    username: 'Max',
    lastUpdated: DateTime.utc(2026, 4, 14),
    googleUser: false,
    userId: 1,
  );

  @override
  User? get user => _testUser;

  @override
  Future<void> loadUser() async {}
}

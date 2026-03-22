import 'package:bierliste/models/group.dart';
import 'package:bierliste/screens/group_overview_page.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('old join per groupId ui is removed from group overview', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: GroupOverviewPage(groupApiService: EmptyGroupApiService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.group_add), findsNothing);
    expect(find.text('Gruppe beitreten'), findsNothing);
    expect(
      find.text('Erstelle eine neue Gruppe oder öffne einen Einladungslink.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('group overview opens personal settings from app bar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/settings': (_) =>
              const Scaffold(body: Text('Persönliche Einstellungen')),
        },
        home: GroupOverviewPage(groupApiService: EmptyGroupApiService()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Persönliche Einstellungen'), findsOneWidget);
  });
}

class EmptyGroupApiService extends GroupApiService {
  @override
  Future<List<Group>> listGroups() async => const [];
}

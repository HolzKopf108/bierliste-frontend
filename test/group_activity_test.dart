import 'package:bierliste/models/group_activity.dart';
import 'package:bierliste/utils/group_activity_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown activity types fall back to unknown', () {
    final activity = GroupActivity.fromJson({
      'id': 42,
      'timestamp': '2026-03-21T12:34:56Z',
      'type': 'SOMETHING_NEW',
      'actor': {'userId': 7, 'usernameSnapshot': 'Alex'},
    });

    expect(activity.type, ActivityType.unknown);
    expect(activity.actorName, 'Alex');
    expect(activity.meta['rawType'], 'SOMETHING_NEW');
  });

  test('group activities response parses items and cursor', () {
    final response = GroupActivitiesResponse.fromJson({
      'items': [
        {
          'id': 1,
          'timestamp': '2026-03-21T12:34:56Z',
          'type': 'USER_JOINED_GROUP',
          'actor': {'userId': 8, 'usernameSnapshot': 'Mia'},
        },
      ],
      'nextCursor': 'cursor-123',
    }, requestedLimit: 50);

    expect(response.items, hasLength(1));
    expect(response.nextCursor, 'cursor-123');
    expect(response.limit, 50);
  });

  test('formatter handles pluralization and self actions', () {
    final single = GroupActivity(
      id: 1,
      timestamp: DateTime(2026, 3, 21, 9, 5),
      type: ActivityType.strichIncremented,
      actorUserId: 5,
      actorName: 'Max',
      targetUserId: 5,
      targetName: 'Max',
      meta: const {'amount': 1},
    );
    final multiple = GroupActivity(
      id: 2,
      timestamp: DateTime(2026, 3, 21, 9, 10),
      type: ActivityType.strichIncremented,
      actorUserId: 5,
      actorName: 'Max',
      targetUserId: 8,
      targetName: 'Mia',
      meta: const {'amount': 2},
    );

    expect(
      GroupActivityFormatter.formatDescription(single),
      'Max hat sich 1 Strich gemacht.',
    );
    expect(
      GroupActivityFormatter.formatDescription(multiple),
      'Max hat Mia 2 Striche gemacht.',
    );
    expect(
      GroupActivityFormatter.formatTimestamp(single.timestamp),
      '21.03.2026 09:05',
    );
  });

  test('formatter renders settings changes with meta values', () {
    final activity = GroupActivity(
      id: 3,
      timestamp: DateTime(2026, 3, 21, 9, 15),
      type: ActivityType.groupSettingsChanged,
      actorName: 'Lena',
      meta: const {
        'changedFields': ['NAME', 'PRICE_PER_STRICH'],
        'oldSettings': {'name': 'Alt', 'pricePerStrich': 1.5},
        'newSettings': {'name': 'Neu', 'pricePerStrich': 2.0},
      },
    );

    expect(
      GroupActivityFormatter.formatDescription(activity),
      'Lena hat Einstellungen geändert: Name: Alt -> Neu, Preis pro Strich: 1,50 € -> 2,00 €.',
    );
  });
}

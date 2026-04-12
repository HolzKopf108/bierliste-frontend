import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/group_member_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group member parses notification-related fields', () {
    final member = GroupMember.fromJson({
      'userId': 7,
      'username': 'Mia',
      'strichCount': 4,
      'role': 'MEMBER',
      'outstandingAmount': 3.5,
      'canReceiveNotification': true,
      'hasPendingNotification': true,
      'lastNotificationSentAt': '2026-03-27T11:45:00Z',
      'lastNotificationConfirmedAt': null,
    });

    expect(member.userId, 7);
    expect(member.outstandingAmount, 3.5);
    expect(member.canReceiveNotification, isTrue);
    expect(member.hasPendingNotification, isTrue);
    expect(
      member.lastNotificationSentAt,
      DateTime.parse('2026-03-27T11:45:00Z'),
    );
    expect(member.lastNotificationConfirmedAt, isNull);
  });

  test('group member notification parses and exposes open state', () {
    final notification = GroupMemberNotification.fromJson({
      'id': 9,
      'groupId': 5,
      'actorUserId': 2,
      'actorUsername': 'Alex',
      'targetUserId': 7,
      'message': 'Bring heute 3,50€ mit',
      'createdAt': '2026-03-27T12:00:00Z',
      'confirmedAt': null,
    });

    expect(notification.id, 9);
    expect(notification.groupId, 5);
    expect(notification.actorUsername, 'Alex');
    expect(notification.message, 'Bring heute 3,50€ mit');
    expect(notification.isOpen, isTrue);
  });
}

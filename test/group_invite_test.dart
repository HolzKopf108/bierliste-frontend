import 'package:bierliste/models/group_invite.dart';
import 'package:bierliste/utils/invite_link_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invite response maps correctly without joinUrl', () {
    final invite = GroupInvite.fromJson({
      'inviteId': 7,
      'token': 'abc123',
      'expiresAt': '2026-03-30T12:34:56Z',
    });

    expect(invite.inviteId, 7);
    expect(invite.token, 'abc123');
    expect(invite.expiresAt, DateTime.parse('2026-03-30T12:34:56Z'));
  });

  test('invite link builder creates custom scheme and share link', () {
    expect(
      InviteLinkBuilder.buildAppLink('abc123'),
      'bierliste://join?token=abc123',
    );
    expect(
      InviteLinkBuilder.buildShareLink('abc123'),
      'https://bierliste.koelker-recke.de/invites/abc123',
    );
  });
}

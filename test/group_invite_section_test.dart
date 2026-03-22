import 'dart:async';

import 'package:bierliste/models/group_invite.dart';
import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/group_settings.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/utils/invite_link_builder.dart';
import 'package:bierliste/widgets/group_invite_section.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  Future<void> pumpInviteSection(
    WidgetTester tester, {
    required GroupInvitePermission invitePermission,
    required GroupMemberRole? ownRole,
    required Future<GroupInvite> Function() onCreateInvite,
    Future<void> Function(String text)? onCopy,
    void Function(String message, {ToastType type})? onFeedback,
    bool isRoleLoading = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupInviteSection(
            groupId: 7,
            invitePermission: invitePermission,
            ownRole: ownRole,
            isRoleLoading: isRoleLoading,
            onCreateInvite: onCreateInvite,
            writeToClipboard: onCopy,
            onFeedback: onFeedback,
          ),
        ),
      ),
    );
  }

  testWidgets('button is disabled for members when only warts may invite', (
    tester,
  ) async {
    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.onlyWarts,
      ownRole: GroupMemberRole.member,
      onCreateInvite: () async => throw UnimplementedError(),
    );

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('createInviteButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('button is visible for members when all members may invite', (
    tester,
  ) async {
    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.allMembers,
      ownRole: GroupMemberRole.member,
      onCreateInvite: () async => throw UnimplementedError(),
    );

    expect(find.byKey(const Key('createInviteButton')), findsOneWidget);
  });

  testWidgets('button is disabled while role is still loading', (tester) async {
    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.allMembers,
      ownRole: GroupMemberRole.member,
      isRoleLoading: true,
      onCreateInvite: () async => throw UnimplementedError(),
    );

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('createInviteButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('successful invite shows share link and QR uses custom scheme', (
    tester,
  ) async {
    const token = 'token-123';
    final expectedQrLink = InviteLinkBuilder.buildAppLink(token);
    final expectedShareLink = InviteLinkBuilder.buildShareLink(token);

    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.onlyWarts,
      ownRole: GroupMemberRole.wart,
      onCreateInvite: () async => const GroupInvite(inviteId: 1, token: token),
    );

    await tester.tap(find.byKey(const Key('createInviteButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inviteLinkText')), findsOneWidget);
    expect(find.text(expectedShareLink), findsOneWidget);

    final qrWidget = tester.widget<QrImageView>(
      find.byKey(const Key('inviteQrCode')),
    );
    expect(qrWidget.semanticsLabel, expectedQrLink);
  });

  testWidgets('copy button copies full link', (tester) async {
    const token = 'token-copy';
    final expectedShareLink = InviteLinkBuilder.buildShareLink(token);
    String? copiedText;
    String? feedbackMessage;

    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.onlyWarts,
      ownRole: GroupMemberRole.wart,
      onCreateInvite: () async => const GroupInvite(inviteId: 2, token: token),
      onCopy: (text) async {
        copiedText = text;
      },
      onFeedback: (message, {type = ToastType.error}) {
        feedbackMessage = message;
      },
    );

    await tester.tap(find.byKey(const Key('createInviteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copyInviteLinkButton')));
    await tester.pumpAndSettle();

    expect(copiedText, expectedShareLink);
    expect(feedbackMessage, 'Link kopiert');
  });

  testWidgets('loading state prevents double requests', (tester) async {
    final completer = Completer<GroupInvite>();
    var requestCount = 0;

    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.onlyWarts,
      ownRole: GroupMemberRole.wart,
      onCreateInvite: () {
        requestCount += 1;
        return completer.future;
      },
    );

    await tester.tap(find.byKey(const Key('createInviteButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('createInviteButton')));
    await tester.pump();

    expect(requestCount, 1);

    completer.complete(const GroupInvite(inviteId: 3, token: 'token-pending'));
    await tester.pumpAndSettle();
  });

  testWidgets('403 while creating invite shows clean message', (tester) async {
    String? feedbackMessage;

    await pumpInviteSection(
      tester,
      invitePermission: GroupInvitePermission.onlyWarts,
      ownRole: GroupMemberRole.wart,
      onCreateInvite: () async {
        throw GroupApiException('Forbidden', statusCode: 403);
      },
      onFeedback: (message, {type = ToastType.error}) {
        feedbackMessage = message;
      },
    );

    await tester.tap(find.byKey(const Key('createInviteButton')));
    await tester.pumpAndSettle();

    expect(feedbackMessage, 'Du darfst keinen Einladungslink erstellen.');
  });
}

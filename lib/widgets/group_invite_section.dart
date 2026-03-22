import 'dart:async';
import 'dart:math' as math;

import 'package:bierliste/models/group_invite.dart';
import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/group_settings.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

typedef InviteCreator = Future<GroupInvite> Function();
typedef InviteClipboardWriter = Future<void> Function(String text);
typedef InviteSectionFeedback = void Function(String message, {ToastType type});

class GroupInviteSection extends StatefulWidget {
  static const requestTimeout = Duration(seconds: 8);

  final int groupId;
  final GroupInvitePermission invitePermission;
  final GroupMemberRole? ownRole;
  final bool isRoleLoading;
  final InviteCreator onCreateInvite;
  final InviteClipboardWriter? writeToClipboard;
  final InviteSectionFeedback? onFeedback;

  const GroupInviteSection({
    super.key,
    required this.groupId,
    required this.invitePermission,
    required this.ownRole,
    required this.isRoleLoading,
    required this.onCreateInvite,
    this.writeToClipboard,
    this.onFeedback,
  });

  static bool canCreateInvite({
    required GroupInvitePermission invitePermission,
    required GroupMemberRole? ownRole,
    required bool isRoleLoading,
  }) {
    if (isRoleLoading) {
      return false;
    }

    switch (invitePermission) {
      case GroupInvitePermission.onlyWarts:
        return ownRole == GroupMemberRole.wart;
      case GroupInvitePermission.allMembers:
        return ownRole == GroupMemberRole.wart ||
            ownRole == GroupMemberRole.member;
    }
  }

  @override
  State<GroupInviteSection> createState() => _GroupInviteSectionState();
}

class _GroupInviteSectionState extends State<GroupInviteSection> {
  bool _isCreatingInvite = false;

  Future<void> _createInvite() async {
    if (_isCreatingInvite) {
      return;
    }

    setState(() => _isCreatingInvite = true);

    try {
      final invite = await widget.onCreateInvite().timeout(
        GroupInviteSection.requestTimeout,
      );
      if (!mounted) {
        return;
      }
      setState(() => _isCreatingInvite = false);
      await _showInviteDialog(invite);
      return;
    } on GroupApiException catch (e) {
      if (!mounted) {
        return;
      }
      _showFeedback(
        _friendlyCreateInviteErrorMessage(e),
        type: _feedbackTypeForCreateInviteError(e),
      );
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      _showFeedback('Keine Verbindung');
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showFeedback('Einladungslink konnte nicht erstellt werden');
    } finally {
      if (mounted && _isCreatingInvite) {
        setState(() => _isCreatingInvite = false);
      }
    }
  }

  Future<void> _showInviteDialog(GroupInvite invite) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          child: _InviteLinkDialog(
            invite: invite,
            writeToClipboard: widget.writeToClipboard,
            onFeedback: widget.onFeedback,
          ),
        );
      },
    );
  }

  String _friendlyCreateInviteErrorMessage(GroupApiException exception) {
    if (_isNetworkError(exception)) {
      return 'Keine Verbindung';
    }

    switch (exception.statusCode) {
      case 403:
        return 'Du darfst keinen Einladungslink erstellen.';
      case 404:
        return 'Gruppe nicht gefunden / kein Zugriff';
      default:
        return exception.message;
    }
  }

  ToastType _feedbackTypeForCreateInviteError(GroupApiException exception) {
    switch (exception.statusCode) {
      case 403:
      case 404:
        return ToastType.warning;
      default:
        return ToastType.error;
    }
  }

  bool _isNetworkError(GroupApiException exception) {
    final normalizedMessage = exception.message.trim().toLowerCase();
    return exception.statusCode == null &&
        (normalizedMessage == 'netzwerkfehler' ||
            normalizedMessage.contains('timeout'));
  }

  void _showFeedback(String message, {ToastType type = ToastType.error}) {
    if (widget.onFeedback != null) {
      widget.onFeedback!(message, type: type);
      return;
    }

    Toast.show(context, message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final canCreateInvite = GroupInviteSection.canCreateInvite(
      invitePermission: widget.invitePermission,
      ownRole: widget.ownRole,
      isRoleLoading: widget.isRoleLoading,
    );

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: const Key('createInviteButton'),
        onPressed: !canCreateInvite || _isCreatingInvite ? null : _createInvite,
        icon: _isCreatingInvite
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.qr_code_2),
        label: Text(
          _isCreatingInvite
              ? 'Einladungslink wird erstellt...'
              : 'Einladungslink erstellen',
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _InviteLinkDialog extends StatelessWidget {
  final GroupInvite invite;
  final InviteClipboardWriter? writeToClipboard;
  final InviteSectionFeedback? onFeedback;

  const _InviteLinkDialog({
    required this.invite,
    this.writeToClipboard,
    this.onFeedback,
  });

  Future<void> _copyInviteLink(BuildContext context) async {
    try {
      final clipboardWriter =
          writeToClipboard ??
          (text) => Clipboard.setData(ClipboardData(text: text));
      await clipboardWriter(invite.joinUrl);

      if (!context.mounted) {
        return;
      }

      if (onFeedback != null) {
        onFeedback!('Link kopiert', type: ToastType.success);
        return;
      }

      Toast.show(context, 'Link kopiert', type: ToastType.success);
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      if (onFeedback != null) {
        onFeedback!(
          'Link konnte nicht kopiert werden',
          type: ToastType.error,
        );
        return;
      }

      Toast.show(context, 'Link konnte nicht kopiert werden');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einladungslink'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 420 ? 16.0 : 24.0;
          final qrSize = math.min(
            constraints.maxWidth - (horizontalPadding * 2),
            constraints.maxHeight * 0.58,
          );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 16),
                      ],
                    ),
                    child: QrImageView(
                      key: const Key('inviteQrCode'),
                      data: invite.joinUrl,
                      semanticsLabel: invite.joinUrl,
                      version: QrVersions.auto,
                      size: qrSize,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Link',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    invite.joinUrl,
                    key: const Key('inviteLinkText'),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('copyInviteLinkButton'),
                    onPressed: () => _copyInviteLink(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('Link kopieren'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

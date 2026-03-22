import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:bierliste/models/group.dart';
import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/group_role_provider.dart';
import 'package:bierliste/routes/app_routes.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/group_settings_api_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/offline_group_activity_service.dart';
import 'package:bierliste/services/offline_group_settings_service.dart';
import 'package:bierliste/services/offline_group_users_service.dart';
import 'package:bierliste/utils/invite_link_parser.dart';
import 'package:bierliste/utils/navigation_helper.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

typedef InviteJoinSuccessHandler = Future<void> Function(Group group);
typedef InviteFeedbackHandler = void Function(String message, {ToastType type});

class InviteLinkService {
  static const _pendingInviteTokenKey = 'pendingInviteToken';
  static const _requestTimeout = Duration(seconds: 8);

  final AppLinks _appLinks;
  final GroupApiService _groupApiService;
  SharedPreferences? _sharedPreferences;

  StreamSubscription<Uri>? _linkSubscription;
  bool _isInitialized = false;
  bool _isHandlingInvite = false;
  String? _pendingInviteToken;

  InviteLinkService({
    AppLinks? appLinks,
    GroupApiService? groupApiService,
    SharedPreferences? sharedPreferences,
  }) : _appLinks = appLinks ?? AppLinks(),
       _groupApiService = groupApiService ?? GroupApiService(),
       _sharedPreferences = sharedPreferences;

  bool get hasPendingInvite =>
      _pendingInviteToken != null && _pendingInviteToken!.trim().isNotEmpty;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _sharedPreferences ??= await SharedPreferences.getInstance();
    _pendingInviteToken = _sharedPreferences!.getString(_pendingInviteTokenKey);

    try {
      final initialUri = await _appLinks.getInitialLink();
      await _captureInviteUri(initialUri, autoProcess: false);
    } on PlatformException catch (e) {
      debugPrint('InviteLinkService Initial-Link Fehler: $e');
    } catch (e) {
      debugPrint('InviteLinkService Initial-Link Fehler: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        unawaited(_captureInviteUri(uri, autoProcess: true));
      },
      onError: (Object error) {
        debugPrint('InviteLinkService Stream-Fehler: $error');
      },
    );

    _isInitialized = true;
  }

  Future<void> storePendingInviteToken(String token) async {
    final sanitizedToken = token.trim();
    if (sanitizedToken.isEmpty) {
      return;
    }

    _sharedPreferences ??= await SharedPreferences.getInstance();
    _pendingInviteToken = sanitizedToken;
    await _sharedPreferences!.setString(_pendingInviteTokenKey, sanitizedToken);
  }

  Future<void> clearPendingInviteToken() async {
    _sharedPreferences ??= await SharedPreferences.getInstance();
    _pendingInviteToken = null;
    await _sharedPreferences!.remove(_pendingInviteTokenKey);
  }

  Future<bool> handlePendingInviteIfPossible({
    BuildContext? context,
    InviteJoinSuccessHandler? onJoinSuccess,
    InviteFeedbackHandler? onMessage,
  }) async {
    final token = _pendingInviteToken?.trim();
    if (token == null || token.isEmpty || _isHandlingInvite) {
      return false;
    }

    final lookupContext = context ?? navigatorKey.currentContext;
    if (lookupContext == null) {
      return false;
    }

    final authProvider = Provider.of<AuthProvider>(
      lookupContext,
      listen: false,
    );
    final userEmail = authProvider.userEmail;
    if (!authProvider.isAuthenticated || userEmail == null) {
      return false;
    }

    _isHandlingInvite = true;

    try {
      final group = await _groupApiService
          .joinGroupByInviteToken(token)
          .timeout(_requestTimeout);

      await clearPendingInviteToken();

      final successContext = _currentMountedNavigatorContext();
      if (successContext == null && onJoinSuccess == null) {
        return false;
      }

      final successHandler =
          onJoinSuccess ??
          (joinedGroup) => _handleJoinSuccess(
            successContext!,
            userEmail,
            joinedGroup,
          );
      await successHandler(group);
      return true;
    } on UnauthorizedException {
      return false;
    } on GroupApiException catch (e) {
      await clearPendingInviteToken();
      _showMessageAfterAsync(
        _friendlyJoinErrorMessage(e),
        type: _feedbackTypeForJoinError(e),
        onMessage: onMessage,
      );
      return false;
    } on TimeoutException {
      await clearPendingInviteToken();
      _showMessageAfterAsync(
        'Keine Verbindung. Bitte Link erneut öffnen.',
        onMessage: onMessage,
      );
      return false;
    } catch (e) {
      debugPrint('InviteLinkService Join-Fehler: $e');
      await clearPendingInviteToken();
      _showMessageAfterAsync(
        'Einladung konnte nicht verarbeitet werden',
        onMessage: onMessage,
      );
      return false;
    } finally {
      _isHandlingInvite = false;
    }
  }

  void dispose() {
    final subscription = _linkSubscription;
    _linkSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _captureInviteUri(Uri? uri, {required bool autoProcess}) async {
    final token = InviteLinkParser.parseToken(uri);
    if (token == null) {
      return;
    }

    await storePendingInviteToken(token);

    if (!autoProcess) {
      return;
    }

    unawaited(handlePendingInviteIfPossible());
  }

  Future<void> _handleJoinSuccess(
    BuildContext context,
    String userEmail,
    Group group,
  ) async {
    unawaited(_refreshJoinedGroupState(context, userEmail, group.id));
    await safeGlobalPushNamedAndRemoveUntil(
      '/groupDetail',
      arguments: AppRoutes.groupArgs(group.id, groupName: group.name),
    );
  }

  Future<void> _refreshJoinedGroupState(
    BuildContext context,
    String userEmail,
    int groupId,
  ) async {
    final groupRoleProvider = Provider.of<GroupRoleProvider>(
      context,
      listen: false,
    );

    unawaited(_runSafely(() => groupRoleProvider.refreshRole(userEmail, groupId)));
    unawaited(
      _runSafely(
        () => OfflineGroupSettingsService.refreshGroupSettings(
          userEmail,
          groupId,
        ),
      ),
    );
    unawaited(
      _runSafely(
        () => OfflineGroupUsersService.refreshGroupMembers(userEmail, groupId),
      ),
    );
    unawaited(
      _runSafely(
        () => OfflineGroupActivityService.refreshGroupActivities(
          userEmail,
          groupId,
        ),
      ),
    );
  }

  Future<void> _runSafely(Future<dynamic> Function() action) async {
    try {
      await action();
    } on GroupSettingsApiException {
      return;
    } catch (_) {
      return;
    }
  }

  String _friendlyJoinErrorMessage(GroupApiException exception) {
    if (_isNetworkError(exception)) {
      return 'Keine Verbindung. Bitte Link erneut öffnen.';
    }

    switch (exception.statusCode) {
      case 403:
        return 'Kein Zugriff auf diese Einladung';
      case 404:
        return 'Einladung ungültig';
      case 410:
        return 'Einladung abgelaufen';
      default:
        return exception.message;
    }
  }

  ToastType _feedbackTypeForJoinError(GroupApiException exception) {
    switch (exception.statusCode) {
      case 403:
      case 404:
      case 410:
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

  void _showMessage(
    BuildContext context,
    String message, {
    ToastType type = ToastType.error,
    InviteFeedbackHandler? onMessage,
  }) {
    if (onMessage != null) {
      onMessage(message, type: type);
      return;
    }

    Toast.show(context, message, type: type);
  }

  void _showMessageAfterAsync(
    String message, {
    ToastType type = ToastType.error,
    InviteFeedbackHandler? onMessage,
  }) {
    final mountedContext = _currentMountedNavigatorContext();
    if (mountedContext == null) {
      onMessage?.call(message, type: type);
      return;
    }

    _showMessage(mountedContext, message, type: type, onMessage: onMessage);
  }

  BuildContext? _currentMountedNavigatorContext() {
    final fallbackContext = navigatorKey.currentContext;
    if (fallbackContext != null && fallbackContext.mounted) {
      return fallbackContext;
    }

    return null;
  }
}

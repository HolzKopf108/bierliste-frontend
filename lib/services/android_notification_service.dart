import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:bierliste/firebase_options.dart';
import 'package:bierliste/routes/app_routes.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:bierliste/services/user_notification_api_service.dart';
import 'package:bierliste/utils/navigation_helper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _pendingNotificationActionPrefsKey =
    'pending_group_notification_action';
const String _registeredAndroidPushTokenPrefsKey =
    'registered_android_push_token';
const String _androidNotificationPermissionPromptedPrefsKey =
    'android_notification_permission_prompted';
const String _groupMemberNotificationType = 'GROUP_MEMBER_NOTIFICATION';
const String _groupMemberNotificationChannelId = 'group_member_notifications';
const String _groupMemberNotificationConfirmActionId =
    'group_member_notification_confirm';

const AndroidNotificationChannel _groupMemberNotificationChannel =
    AndroidNotificationChannel(
      _groupMemberNotificationChannelId,
      'Gruppen-Benachrichtigungen',
      description: 'Benachrichtigungen für Gruppenmitglieder',
      importance: Importance.high,
    );
const InitializationSettings _androidNotificationInitializationSettings =
    InitializationSettings(
      android: AndroidInitializationSettings('notification_icon'),
    );

FlutterLocalNotificationsPlugin? _backgroundLocalNotificationsPlugin;
bool _backgroundLocalNotificationsInitialized = false;

bool get _supportsAndroidNotifications =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _supportsFirebaseCoreInitialization {
  if (kIsWeb) {
    return true;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

Future<bool> ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) {
    return true;
  }
  if (!_supportsFirebaseCoreInitialization) {
    return false;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return true;
  } on UnsupportedError catch (e) {
    debugPrint('AndroidNotificationService Firebase unsupported: $e');
    return false;
  } catch (e) {
    debugPrint('AndroidNotificationService Firebase-Init fehlgeschlagen: $e');
    return false;
  }
}

Future<SharedPreferences?> _sharedPreferencesOrNull() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('AndroidNotificationService SharedPreferences Fehler: $e');
    return null;
  }
}

void _handleForegroundNotificationResponse(NotificationResponse response) {
  AndroidNotificationService.instance._handleNotificationResponse(response);
}

Future<void> _initializeLocalNotificationsPlugin(
  FlutterLocalNotificationsPlugin plugin, {
  required DidReceiveNotificationResponseCallback
  onDidReceiveNotificationResponse,
  required DidReceiveBackgroundNotificationResponseCallback
  onDidReceiveBackgroundNotificationResponse,
}) async {
  await plugin.initialize(
    settings: _androidNotificationInitializationSettings,
    onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        onDidReceiveBackgroundNotificationResponse,
  );

  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_groupMemberNotificationChannel);
}

Future<FlutterLocalNotificationsPlugin>
_ensureBackgroundLocalNotificationsPlugin() async {
  final plugin = _backgroundLocalNotificationsPlugin ??=
      FlutterLocalNotificationsPlugin();
  if (_backgroundLocalNotificationsInitialized) {
    return plugin;
  }

  await _initializeLocalNotificationsPlugin(
    plugin,
    onDidReceiveNotificationResponse: _handleForegroundNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        handleBackgroundNotificationResponse,
  );
  _backgroundLocalNotificationsInitialized = true;
  return plugin;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (!await ensureFirebaseInitialized()) {
    return;
  }

  await _ensureBackgroundLocalNotificationsPlugin();
  await _showAndroidGroupNotificationFromData(message.data);
}

@pragma('vm:entry-point')
void handleBackgroundNotificationResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  unawaited(_persistPendingActionFromNotificationResponse(response));
}

class AndroidNotificationService {
  AndroidNotificationService._();

  static final AndroidNotificationService instance =
      AndroidNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final UserNotificationApiService _userNotificationApiService =
      UserNotificationApiService();
  final StreamController<int> _incomingGroupNotificationController =
      StreamController<int>.broadcast();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  bool _initialized = false;
  bool _firebaseReady = false;
  bool _firebaseInitializationAttempted = false;

  Stream<int> get incomingGroupNotifications =>
      _incomingGroupNotificationController.stream;

  Future<void> initialize() async {
    if (_initialized || !_supportsAndroidNotifications) {
      return;
    }

    _initialized = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _initializeLocalNotifications();
    await _restoreNotificationLaunchDetails();
    await _initializeFirebaseIfPossible();
  }

  Future<void> syncAndroidNotificationState({
    bool requestPermissionIfNeeded = false,
  }) async {
    if (!_supportsAndroidNotifications) {
      return;
    }

    await initialize();

    if (!_firebaseReady) {
      await _initializeFirebaseIfPossible();
    }
    if (!_firebaseReady) {
      return;
    }

    final userEmail = await TokenService.getUserEmail();
    if (userEmail == null || userEmail.trim().isEmpty) {
      return;
    }

    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      return;
    }
    final storedToken = _storedRegisteredToken(prefs);
    final notificationsEnabled = await _areNotificationsEnabled(
      prefs: prefs,
      requestPermissionIfNeeded: requestPermissionIfNeeded,
    );

    if (!notificationsEnabled) {
      final removed = await _tryUnregisterToken(storedToken);
      if (removed) {
        await _clearStoredRegisteredToken(prefs);
      }
      return;
    }

    final currentToken = await _getCurrentFcmToken();
    if (currentToken == null) {
      final removed = await _tryUnregisterToken(storedToken);
      if (removed) {
        await _clearStoredRegisteredToken(prefs);
      }
      return;
    }

    if (storedToken == currentToken) {
      return;
    }

    if (storedToken != null && storedToken.isNotEmpty) {
      await _tryUnregisterToken(storedToken);
    }

    try {
      await _userNotificationApiService.registerAndroidToken(currentToken);
      await prefs.setString(_registeredAndroidPushTokenPrefsKey, currentToken);
    } catch (e) {
      debugPrint('AndroidNotificationService registerAndroidToken Fehler: $e');
    }
  }

  Future<void> clearAuthenticatedSession() async {
    if (!_supportsAndroidNotifications) {
      return;
    }

    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      return;
    }
    final storedToken = _storedRegisteredToken(prefs);
    if (storedToken != null && storedToken.isNotEmpty) {
      await _tryUnregisterToken(storedToken);
    }
    await _clearStoredRegisteredToken(prefs);
  }

  Future<Map<String, dynamic>?> consumePendingNavigationArgs() async {
    final action = await _readPendingAction();
    if (action == null) {
      return null;
    }

    if (!action.shouldConfirm) {
      await _clearPendingAction();
    }

    return AppRoutes.groupArgs(action.groupId, groupName: action.groupName);
  }

  Future<int?> pendingConfirmationNotificationIdForGroup(int groupId) async {
    final action = await _readPendingAction();
    if (action == null) {
      return null;
    }
    if (!action.shouldConfirm || action.groupId != groupId) {
      return null;
    }
    return action.notificationId;
  }

  Future<void> clearPendingConfirmation(int groupId, int notificationId) async {
    final action = await _readPendingAction();
    if (action == null) {
      return;
    }
    if (action.groupId != groupId || action.notificationId != notificationId) {
      return;
    }
    await _clearPendingAction();
  }

  Future<void> navigateToPendingGroupIfPossible() async {
    if (!await _hasAuthenticatedUser()) {
      return;
    }

    final args = await consumePendingNavigationArgs();
    if (args == null) {
      return;
    }

    await safeGlobalPushNamedAndRemoveUntil('/groupDetail', arguments: args);
  }

  void _notifyIncomingGroupNotification(int groupId) {
    if (_incomingGroupNotificationController.isClosed) {
      return;
    }
    _incomingGroupNotificationController.add(groupId);
  }

  @visibleForTesting
  void debugDispatchIncomingGroupNotification(int groupId) {
    _notifyIncomingGroupNotification(groupId);
  }

  Future<void> _initializeLocalNotifications() async {
    await _initializeLocalNotificationsPlugin(
      _localNotifications,
      onDidReceiveNotificationResponse: _handleForegroundNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          handleBackgroundNotificationResponse,
    );
  }

  Future<void> _restoreNotificationLaunchDetails() async {
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;

    if (launchDetails?.didNotificationLaunchApp != true || response == null) {
      return;
    }

    await _persistPendingActionFromNotificationResponse(response);
  }

  Future<void> _initializeFirebaseIfPossible() async {
    if (_firebaseReady || _firebaseInitializationAttempted) {
      return;
    }

    _firebaseInitializationAttempted = true;

    if (!await ensureFirebaseInitialized()) {
      return;
    }
    _firebaseReady = true;

    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen((token) {
          unawaited(_handleTokenRefresh(token));
        });
    _onMessageSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showAndroidGroupNotificationFromData(message.data));
    });
    _onMessageOpenedAppSubscription ??= FirebaseMessaging.onMessageOpenedApp
        .listen((message) {
          unawaited(
            _persistPendingActionFromRemoteMessage(
              message,
              shouldConfirm: false,
              overwriteExisting: false,
            ),
          );
          unawaited(navigateToPendingGroupIfPossible());
        });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await _persistPendingActionFromRemoteMessage(
        initialMessage,
        shouldConfirm: false,
        overwriteExisting: false,
      );
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    unawaited(_persistPendingActionFromNotificationResponse(response));
    unawaited(navigateToPendingGroupIfPossible());
  }

  Future<void> _handleTokenRefresh(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return;
    }

    await syncAndroidNotificationState();
  }

  Future<bool> _areNotificationsEnabled({
    required SharedPreferences prefs,
    required bool requestPermissionIfNeeded,
  }) async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return false;
    }

    var enabled = await androidPlugin.areNotificationsEnabled() ?? false;
    if (enabled || !requestPermissionIfNeeded) {
      return enabled;
    }

    final alreadyPrompted =
        prefs.getBool(_androidNotificationPermissionPromptedPrefsKey) == true;
    if (alreadyPrompted) {
      return false;
    }

    await prefs.setBool(_androidNotificationPermissionPromptedPrefsKey, true);
    enabled = await androidPlugin.requestNotificationsPermission() ?? false;
    return enabled;
  }

  Future<String?> _getCurrentFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final normalizedToken = token?.trim();
      if (normalizedToken == null || normalizedToken.isEmpty) {
        return null;
      }
      return normalizedToken;
    } catch (e) {
      debugPrint('AndroidNotificationService getToken Fehler: $e');
      return null;
    }
  }

  String? _storedRegisteredToken(SharedPreferences prefs) {
    final storedToken = prefs.getString(_registeredAndroidPushTokenPrefsKey);
    if (storedToken == null || storedToken.trim().isEmpty) {
      return null;
    }
    return storedToken.trim();
  }

  Future<void> _clearStoredRegisteredToken(SharedPreferences prefs) async {
    await prefs.remove(_registeredAndroidPushTokenPrefsKey);
  }

  Future<bool> _tryUnregisterToken(String? token) async {
    final normalizedToken = token?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      return true;
    }

    try {
      await _userNotificationApiService.unregisterAndroidToken(normalizedToken);
      return true;
    } catch (e) {
      debugPrint(
        'AndroidNotificationService unregisterAndroidToken Fehler: $e',
      );
      return false;
    }
  }

  Future<bool> _hasAuthenticatedUser() async {
    final userEmail = await TokenService.getUserEmail();
    return userEmail != null && userEmail.trim().isNotEmpty;
  }

  Future<_PendingNotificationAction?> _readPendingAction() async {
    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      return null;
    }
    final rawAction = prefs.getString(_pendingNotificationActionPrefsKey);
    if (rawAction == null || rawAction.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawAction);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_pendingNotificationActionPrefsKey);
        return null;
      }

      return _PendingNotificationAction.fromJson(decoded);
    } catch (_) {
      await prefs.remove(_pendingNotificationActionPrefsKey);
      return null;
    }
  }

  Future<void> _clearPendingAction() async {
    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      return;
    }
    await prefs.remove(_pendingNotificationActionPrefsKey);
  }
}

Future<void> _persistPendingActionFromRemoteMessage(
  RemoteMessage message, {
  required bool shouldConfirm,
  required bool overwriteExisting,
}) async {
  final action = _PendingNotificationAction.fromDataMap(
    message.data,
    shouldConfirm: shouldConfirm,
  );
  if (action == null) {
    return;
  }

  await _persistPendingAction(action, overwriteExisting: overwriteExisting);
}

Future<void> _persistPendingActionFromNotificationResponse(
  NotificationResponse response,
) async {
  final action = _PendingNotificationAction.fromNotificationResponse(response);
  if (action == null) {
    return;
  }

  await _persistPendingAction(action, overwriteExisting: true);
}

Future<void> _persistPendingAction(
  _PendingNotificationAction action, {
  required bool overwriteExisting,
}) async {
  final prefs = await _sharedPreferencesOrNull();
  if (prefs == null) {
    return;
  }
  if (!overwriteExisting &&
      prefs.containsKey(_pendingNotificationActionPrefsKey)) {
    return;
  }

  await prefs.setString(
    _pendingNotificationActionPrefsKey,
    jsonEncode(action.toJson()),
  );
}

Future<void> _showAndroidGroupNotificationFromData(
  Map<String, dynamic> data,
) async {
  if (!_supportsAndroidNotifications) {
    return;
  }

  final action = _PendingNotificationAction.fromDataMap(
    data,
    shouldConfirm: false,
  );
  if (action == null) {
    return;
  }

  AndroidNotificationService.instance._notifyIncomingGroupNotification(
    action.groupId,
  );

  final plugin = await _ensureBackgroundLocalNotificationsPlugin();

  final title = action.title?.trim().isNotEmpty == true
      ? action.title!.trim()
      : action.groupName?.trim().isNotEmpty == true
      ? action.groupName!.trim()
      : 'Bierliste';

  final body = action.message.trim();
  if (body.isEmpty) {
    return;
  }

  try {
    await plugin.show(
      id: action.notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _groupMemberNotificationChannel.id,
          _groupMemberNotificationChannel.name,
          channelDescription: _groupMemberNotificationChannel.description,
          icon: 'notification_icon',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              _groupMemberNotificationConfirmActionId,
              'Bring ich mit',
              cancelNotification: true,
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      payload: jsonEncode(action.toJson()),
    );
  } catch (e) {
    debugPrint('AndroidNotificationService plugin.show Fehler: $e');
  }
}

class _PendingNotificationAction {
  final int groupId;
  final int notificationId;
  final String message;
  final String? groupName;
  final String? title;
  final bool shouldConfirm;

  const _PendingNotificationAction({
    required this.groupId,
    required this.notificationId,
    required this.message,
    required this.shouldConfirm,
    this.groupName,
    this.title,
  });

  factory _PendingNotificationAction.fromJson(Map<String, dynamic> json) {
    return _PendingNotificationAction(
      groupId: _toInt(json['groupId']),
      notificationId: _toInt(json['notificationId']),
      message: (json['message'] ?? '').toString(),
      groupName: _toOptionalString(json['groupName']),
      title: _toOptionalString(json['title']),
      shouldConfirm: json['shouldConfirm'] == true,
    );
  }

  static _PendingNotificationAction? fromDataMap(
    Map<String, dynamic> data, {
    required bool shouldConfirm,
  }) {
    final type = data['type']?.toString().trim();
    if (type != _groupMemberNotificationType) {
      return null;
    }

    final groupId = _tryToInt(data['groupId']);
    final notificationId = _tryToInt(data['notificationId']);
    final message = data['message']?.toString() ?? '';

    if (groupId == null || notificationId == null || message.trim().isEmpty) {
      return null;
    }

    return _PendingNotificationAction(
      groupId: groupId,
      notificationId: notificationId,
      message: message,
      groupName: _toOptionalString(data['groupName']),
      title: _toOptionalString(data['title']),
      shouldConfirm: shouldConfirm,
    );
  }

  static _PendingNotificationAction? fromNotificationResponse(
    NotificationResponse response,
  ) {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final action = _PendingNotificationAction.fromJson(decoded);
      if (response.actionId == _groupMemberNotificationConfirmActionId) {
        return action.copyWith(shouldConfirm: true);
      }
      return action.copyWith(shouldConfirm: false);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'notificationId': notificationId,
      'message': message,
      if (groupName != null) 'groupName': groupName,
      if (title != null) 'title': title,
      'shouldConfirm': shouldConfirm,
    };
  }

  _PendingNotificationAction copyWith({bool? shouldConfirm}) {
    return _PendingNotificationAction(
      groupId: groupId,
      notificationId: notificationId,
      message: message,
      groupName: groupName,
      title: title,
      shouldConfirm: shouldConfirm ?? this.shouldConfirm,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.parse(value.toString());
  }

  static int? _tryToInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString().trim());
  }

  static String? _toOptionalString(dynamic value) {
    final normalizedValue = value?.toString().trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return null;
    }
    return normalizedValue;
  }
}

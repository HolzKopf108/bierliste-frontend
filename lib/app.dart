import 'dart:async';

import 'package:bierliste/providers/user_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'providers/group_role_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/app_routes.dart';
import 'services/android_notification_service.dart';
import 'services/http_service.dart';
import 'services/pending_sync_service.dart';
import 'providers/auth_provider.dart';
import 'main.dart';
import 'config/app_theme.dart';

class BierlisteApp extends StatefulWidget {
  const BierlisteApp({super.key});

  @override
  State<BierlisteApp> createState() => _BierlisteAppState();
}

class _BierlisteAppState extends State<BierlisteApp>
    with WidgetsBindingObserver {
  bool _bindingsConfigured = false;
  AuthProvider? _authProvider;
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _configureBindings();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authProvider?.removeListener(_handleAuthStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    final authProvider = _authProvider;
    if (authProvider == null || !authProvider.isAuthenticated) {
      return;
    }

    unawaited(
      AndroidNotificationService.instance.syncAndroidNotificationState(),
    );
    unawaited(
      AndroidNotificationService.instance.navigateToPendingGroupIfPossible(),
    );
  }

  void _configureBindings() {
    if (_bindingsConfigured) {
      return;
    }

    final syncProvider = context.read<SyncProvider>();
    final authProvider = context.read<AuthProvider>();

    HttpService.onUnauthorized = (reason) {
      return authProvider.logout(reason: reason);
    };

    syncProvider.registerSyncHandler(() async {
      final userEmail = authProvider.userEmail;
      if (!authProvider.isAuthenticated || userEmail == null) {
        return true;
      }

      try {
        return await PendingSyncService.syncPendingOperations(userEmail);
      } on UnauthorizedException {
        return false;
      }
    });

    authProvider.onLogoutCallback = () {
      final userProvider = Provider.of<UserProvider>(
        navigatorKey.currentContext!,
        listen: false,
      );
      final groupRoleProvider = Provider.of<GroupRoleProvider>(
        navigatorKey.currentContext!,
        listen: false,
      );
      userProvider.clearUser();
      groupRoleProvider.clear();
    };

    _authProvider = authProvider;
    _wasAuthenticated = authProvider.isAuthenticated;
    authProvider.addListener(_handleAuthStateChanged);
    _bindingsConfigured = true;
  }

  void _handleAuthStateChanged() {
    final authProvider = _authProvider;
    if (authProvider == null) {
      return;
    }

    final isAuthenticated = authProvider.isAuthenticated;
    if (isAuthenticated && !_wasAuthenticated) {
      unawaited(
        AndroidNotificationService.instance.syncAndroidNotificationState(
          requestPermissionIfNeeded: true,
        ),
      );
    }

    _wasAuthenticated = isAuthenticated;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Bierliste',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      initialRoute: '/',
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}

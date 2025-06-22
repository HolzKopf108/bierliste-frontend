import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/app_routes.dart';
import 'services/counter_api_service.dart';
import 'services/http_service.dart';
import 'providers/auth_provider.dart';
import 'main.dart';
import 'config/app_theme.dart';

class BierlisteApp extends StatelessWidget {
  const BierlisteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    bool refreshCheckedAfterStartup = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      HttpService.onUnauthorized = () {
        authProvider.logout();
        Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      };

      syncProvider.onReconnected = () async {
        if (!refreshCheckedAfterStartup) {
          refreshCheckedAfterStartup = true;

          if (!authProvider.isAuthenticated) return;

          final refreshed = await HttpService.refreshTokens();
          if (!refreshed) {
            await authProvider.logout();
            navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
            return;
          }
        }

        final userEmail = authProvider.userEmail;
        if (userEmail == null) return;

        syncProvider.setIsSyncing(true);
        final success = await CounterApiService().syncPendingStriche(userEmail);
        syncProvider.setIsSyncing(false);

        if (!success) {
          debugPrint("Automatischer Sync fehlgeschlagen");
        }
      };
    });

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


import 'package:bierliste/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/app_routes.dart';
import 'services/group_counter_api_service.dart';
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      HttpService.onUnauthorized = (reason) {
        return authProvider.logout(reason: reason);
      };

      syncProvider.registerSyncHandler(() async {
        final userEmail = authProvider.userEmail;
        if (!authProvider.isAuthenticated || userEmail == null) {
          return true;
        }

        try {
          return await GroupCounterApiService().syncPendingCounterOperations(
            userEmail,
          );
        } on UnauthorizedException {
          return false;
        }
      });

      authProvider.onLogoutCallback = () {
        final userProvider = Provider.of<UserProvider>(
          navigatorKey.currentContext!,
          listen: false,
        );
        userProvider.clearUser();
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

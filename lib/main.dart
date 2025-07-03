import 'package:bierliste/models/user.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';
import 'services/connectivity_service.dart';
import 'app.dart';
import 'package:bierliste/models/user_settings.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Hive.initFlutter();
  Hive.registerAdapter(UserSettingsAdapter());
  Hive.registerAdapter(UserAdapter());

  final themeProvider = ThemeProvider();
  themeProvider.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        Provider(create: (_) => ConnectivityService()),
      ],
      child: const BierlisteApp(),
    ),
  );
}

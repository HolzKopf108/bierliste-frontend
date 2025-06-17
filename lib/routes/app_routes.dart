import 'package:bierliste/screens/group_overview_page.dart';
import 'package:flutter/material.dart';
import '../screens/loading_page.dart';
import '../screens/login_page.dart';
import '../screens/counter_page.dart';
import '../screens/settings_theme_page.dart';
import '../screens/settings_overview_page.dart';
import '../screens/group_home_page.dart';
import '../screens/settings_profil_page.dart';
import '../screens/group_users_page.dart';
import '../screens/group_activity_page.dart';
import '../screens/group_settings_page.dart';
import '../screens/register_page.dart';
import '../screens/verify_page.dart';
import '../screens/forgot_password_page.dart';

class AppRoutes {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return _default(MaterialPageRoute(builder: (_) => const LoadingPage()));
      case '/register':
        return _slide(const RegisterPage());
      case '/verify':
        return _slide(VerifyPage(email: settings.arguments as String));
      case '/login':
        return _default(MaterialPageRoute(builder: (_) => const LoginPage()));
      case '/forgotPassword':
        return _slide(ForgotPasswordPage(email: settings.arguments as String));
      case '/counter':
        return _slide(const CounterPage());
      case '/settings':
        return _slide(const SettingsOverviewPage());
      case '/settingsTheme':
        return _slide(const SettingsThemePage());
      case '/settingsProfil':
        return _slide(const SettingsProfilPage());
      case '/groups':
        return _slide(GroupOverviewPage(previousGroup: settings.arguments as String?));
      case '/groupDetail':
        return _slide(GroupHomePage(groupName: settings.arguments as String));
      case '/groupUsers':
        return _slide(GroupUsersPage(groupName: settings.arguments as String));
      case '/groupActivity': {
        final args = settings.arguments as Map<String, String>?;

        if (args == null ||
            !args.containsKey('groupId') ||
            !args.containsKey('groupName') ||
            !args.containsKey('currentUserId')) {
          return _default(
            MaterialPageRoute(builder: (_) => const LoadingPage()),
          );
        }

        return _slide(
          GroupActivityPage(
            groupId: args['groupId']!,
            groupName: args['groupName']!,
            currentUserId: args['currentUserId']!,
          ),
        );
      }
      case '/groupSettings':
        return _slide(GroupSettingsPage(groupId: settings.arguments as int));
      default:
        return _default(MaterialPageRoute(builder: (_) => const LoadingPage()));
    }
  }

  static Route _slide(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.ease;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  static Route _default(Route route) => route;
}

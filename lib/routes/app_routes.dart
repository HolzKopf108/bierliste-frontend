import 'package:bierliste/screens/group_overview_page.dart';
import 'package:flutter/material.dart';
import '../screens/loading_page.dart';
import '../screens/login_page.dart';
import '../screens/counter_page.dart';
import '../screens/settings_theme_page.dart';
import '../screens/settings_overview_page.dart';
import '../screens/group_home_page.dart';

class AppRoutes {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return _default(MaterialPageRoute(builder: (_) => const LoadingPage()));
      case '/login':
        return _default(MaterialPageRoute(builder: (_) => const LoginPage()));
      case '/counter':
        return _slide(const CounterPage());
      case '/settings':
        return _slide(const SettingsOverviewPage());
      case '/theme':
        return _slide(const SettingsThemePage());
      case '/groups':
        return _slide(const GroupOverviewPage());
      case '/groupDetail':
        return _slide(GroupHomePage(groupName: settings.arguments as String));
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

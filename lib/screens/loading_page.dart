import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  late final AuthProvider _authProvider;

  @override
  void initState() {
    super.initState();
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider.initialize();
    _authProvider.addListener(_authStateChanged);
  }

  void _authStateChanged() {
    if (_authProvider.isInitialized) {
      _handleNavigation(_authProvider);
    }
  }

  Future<void> _handleNavigation(AuthProvider authProvider) async {
    if (!mounted) return;

    if (!authProvider.isAuthenticated) {
      await authProvider.logout();
    }

    _authProvider.removeListener(_authStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      safePushReplacementNamed(
        context,
        authProvider.isAuthenticated ? '/counter' : '/login',
      );
    });
  }

  @override
  void dispose() {
    _authProvider.removeListener(_authStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

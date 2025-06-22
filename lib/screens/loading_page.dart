import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.initialize();
    authProvider.addListener(_authStateChanged);
  }

  void _authStateChanged() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.isInitialized) {
      _handleNavigation(authProvider);
    }
  }

  Future<void> _handleNavigation(AuthProvider authProvider) async {
    if (!mounted) return;

    if (!authProvider.isAuthenticated) {
      await authProvider.logout(); 
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacementNamed(
        authProvider.isAuthenticated ? '/counter' : '/login',
      );
    });
  }

  @override
  void dispose() {
    Provider.of<AuthProvider>(context, listen: false).removeListener(_authStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

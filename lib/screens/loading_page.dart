import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/group_api_service.dart';
import '../services/http_service.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  late final AuthProvider _authProvider;
  final GroupApiService _groupApiService = GroupApiService();

  @override
  void initState() {
    super.initState();
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider.addListener(_authStateChanged);
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await _authProvider.initialize();

    if (!mounted) {
      return;
    }

    if (_authProvider.isInitialized) {
      await _handleNavigation(_authProvider);
    }
  }

  void _authStateChanged() {
    if (_authProvider.isInitialized) {
      _handleNavigation(_authProvider);
    }
  }

  Future<void> _handleNavigation(AuthProvider authProvider) async {
    if (!mounted) return;

    _authProvider.removeListener(_authStateChanged);

    if (!authProvider.isAuthenticated) {
      await authProvider.logout(reason: authProvider.authErrorMessage);
      return;
    }

    Map<String, dynamic>? targetGroupArgs;
    if (authProvider.isAuthenticated) {
      targetGroupArgs = await _resolveInitialGroup();
      if (!mounted) return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (authProvider.isAuthenticated) {
        if (targetGroupArgs != null) {
          safePushReplacementNamed(
            context,
            '/groupDetail',
            arguments: targetGroupArgs,
          );
        } else {
          safePushReplacementNamed(context, '/groups');
        }
      } else {
        safePushReplacementNamed(context, '/login');
      }
    });
  }

  Future<Map<String, dynamic>?> _resolveInitialGroup() async {
    try {
      final groups = await _groupApiService.listGroups();
      if (groups.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('favoriteGroupId');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final favoriteGroupId = prefs.getInt('favoriteGroupId');

      final favoriteGroup = groups.where(
        (group) => group.id == favoriteGroupId,
      );
      final initialGroup = favoriteGroup.isNotEmpty
          ? favoriteGroup.first
          : groups.first;

      if (favoriteGroupId != initialGroup.id) {
        await prefs.setInt('favoriteGroupId', initialGroup.id);
      }

      return {'groupId': initialGroup.id, 'groupName': initialGroup.name};
    } on UnauthorizedException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _authProvider.removeListener(_authStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

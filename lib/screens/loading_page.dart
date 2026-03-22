import 'dart:async';

import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/group.dart';
import '../providers/auth_provider.dart';
import '../routes/app_routes.dart';
import '../services/group_api_service.dart';
import '../services/invite_link_service.dart';
import '../services/offline_group_activity_service.dart';
import '../services/offline_group_users_service.dart';
import '../services/http_service.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  late final AuthProvider _authProvider;
  final GroupApiService _groupApiService = GroupApiService();
  bool _isHandlingNavigation = false;

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
    if (!mounted || _isHandlingNavigation) return;
    _isHandlingNavigation = true;

    _authProvider.removeListener(_authStateChanged);

    if (!authProvider.isAuthenticated) {
      await authProvider.logout(reason: authProvider.authErrorMessage);
      return;
    }

    Map<String, dynamic>? targetGroupArgs;
    if (authProvider.isAuthenticated) {
      final inviteLinkService = context.read<InviteLinkService>();
      final inviteHandled = await inviteLinkService.handlePendingInviteIfPossible(
        context: context,
      );
      if (!mounted) return;
      if (inviteHandled) {
        return;
      }

      targetGroupArgs = await _resolveInitialGroup();
      if (!mounted) return;
    }

    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      if (targetGroupArgs != null) {
        await safePushReplacementNamed(
          context,
          '/groupDetail',
          arguments: targetGroupArgs,
        );
      } else {
        await safePushReplacementNamed(context, '/groups');
      }
    } else {
      await safePushReplacementNamed(context, '/login');
    }
  }

  Future<Map<String, dynamic>?> _resolveInitialGroup() async {
    try {
      final groups = await _groupApiService.listGroups();
      final userEmail = _authProvider.userEmail;
      if (userEmail != null && groups.isNotEmpty) {
        unawaited(_syncGroupCachesInBackground(userEmail, groups));
      }

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

      return AppRoutes.groupArgs(initialGroup.id, groupName: initialGroup.name);
    } on UnauthorizedException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncGroupCachesInBackground(
    String userEmail,
    List<Group> groups,
  ) async {
    final groupIds = groups.map((group) => group.id).toList(growable: false);
    if (groupIds.isEmpty) {
      return;
    }

    try {
      await Future.wait([
        OfflineGroupUsersService.syncGroupMembersInBackground(
          userEmail,
          groupIds,
        ),
        OfflineGroupActivityService.syncGroupActivitiesInBackground(
          userEmail,
          groupIds,
        ),
      ]);
    } on UnauthorizedException {
      return;
    } catch (_) {
      return;
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

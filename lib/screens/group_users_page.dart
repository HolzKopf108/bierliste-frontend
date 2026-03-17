import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group_member.dart';
import '../providers/auth_provider.dart';
import '../providers/group_role_provider.dart';
import '../providers/sync_provider.dart';
import '../services/connectivity_service.dart';
import '../services/group_api_service.dart';
import '../services/offline_group_users_service.dart';
import '../services/http_service.dart';
import '../widgets/toast.dart';

enum SortOption { alphabet, strichCount }

enum _MemberAction { promoteToWart, demoteToMember }

class GroupUsersPage extends StatefulWidget {
  final int groupId;
  final String? groupName;

  const GroupUsersPage({super.key, required this.groupId, this.groupName});

  @override
  State<GroupUsersPage> createState() => _GroupUsersPageState();
}

class _GroupUsersPageState extends State<GroupUsersPage> {
  List<GroupMember> _members = [];
  SortOption _sortOption = SortOption.alphabet;
  bool _isLoading = true;
  int? _updatingMemberUserId;
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final userEmail = context.read<AuthProvider>().userEmail;
    final groupRoleProvider = context.read<GroupRoleProvider>();

    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    if (userEmail == null) {
      if (!mounted) return;
      setState(() {
        _members = [];
        _isLoading = false;
        _loadErrorMessage = 'Mitglieder konnten nicht geladen werden';
      });
      return;
    }

    final cachedMembers = await OfflineGroupUsersService.getGroupMembers(
      userEmail,
      widget.groupId,
    );

    if (!mounted) return;

    if (cachedMembers != null) {
      setState(() {
        _members = cachedMembers;
        _isLoading = false;
        _loadErrorMessage = null;
      });
    }

    unawaited(
      groupRoleProvider.loadRole(userEmail, widget.groupId, forceRefresh: true),
    );

    try {
      if (await ConnectivityService.isOnline()) {
        final members = await OfflineGroupUsersService.refreshGroupMembers(
          userEmail,
          widget.groupId,
        );
        if (!mounted) return;

        setState(() {
          _members = members;
          _isLoading = false;
          _loadErrorMessage = null;
        });
        return;
      }

      if (cachedMembers != null) {
        return;
      }

      await _loadCachedMembers(
        userEmail,
        fallbackErrorMessage: 'Mitglieder konnten nicht geladen werden',
      );
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } on GroupApiException catch (e) {
      if (cachedMembers != null) {
        return;
      }
      await _loadCachedMembers(userEmail, fallbackErrorMessage: e.message);
    } on TimeoutException {
      if (cachedMembers != null) {
        return;
      }
      await _loadCachedMembers(
        userEmail,
        fallbackErrorMessage: 'Mitglieder konnten nicht geladen werden',
      );
    } catch (_) {
      if (cachedMembers != null) {
        return;
      }
      await _loadCachedMembers(
        userEmail,
        fallbackErrorMessage: 'Mitglieder konnten nicht geladen werden',
      );
    }
  }

  Future<void> _loadCachedMembers(
    String userEmail, {
    required String fallbackErrorMessage,
  }) async {
    final cachedMembers = await OfflineGroupUsersService.getGroupMembers(
      userEmail,
      widget.groupId,
    );

    if (!mounted) return;

    if (cachedMembers != null) {
      setState(() {
        _members = cachedMembers;
        _isLoading = false;
        _loadErrorMessage = null;
      });
      return;
    }

    setState(() {
      _members = [];
      _isLoading = false;
      _loadErrorMessage = fallbackErrorMessage;
    });
  }

  List<GroupMember> _sortedMembers() {
    final sorted = List<GroupMember>.from(_members);

    if (_sortOption == SortOption.alphabet) {
      sorted.sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
      return sorted;
    }

    sorted.sort((a, b) {
      final countCompare = b.strichCount.compareTo(a.strichCount);
      if (countCompare != 0) {
        return countCompare;
      }

      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    return sorted;
  }

  String _strichLabel(int strichCount) {
    return strichCount == 1 ? 'Strich' : 'Striche';
  }

  Future<void> _handleMemberAction(
    GroupMember member,
    _MemberAction action,
  ) async {
    if (_updatingMemberUserId != null) {
      return;
    }

    final userEmail = context.read<AuthProvider>().userEmail;
    final syncProvider = context.read<SyncProvider>();
    if (userEmail == null) {
      Toast.show(context, 'Berechtigung konnte nicht geprüft werden');
      return;
    }

    setState(() {
      _updatingMemberUserId = member.userId;
    });

    try {
      final result = switch (action) {
        _MemberAction.promoteToWart =>
          await OfflineGroupUsersService.promoteMember(
            userEmail,
            widget.groupId,
            member,
          ),
        _MemberAction.demoteToMember =>
          await OfflineGroupUsersService.demoteMember(
            userEmail,
            widget.groupId,
            member,
          ),
      };
      if (!mounted) return;

      setState(() {
        _members = result.members;
        _loadErrorMessage = null;
      });

      if (result.errorMessage != null) {
        Toast.show(context, result.errorMessage!, type: ToastType.warning);
      } else {
        Toast.show(
          context,
          'Rollenänderung gespeichert',
          type: ToastType.success,
        );
      }

      if (result.hasPendingSync) {
        unawaited(syncProvider.markPendingSync());
      }
    } on UnauthorizedException {
      if (!mounted) return;
      Toast.show(context, 'Aktion nicht erlaubt', type: ToastType.warning);
    } catch (_) {
      if (!mounted) return;
      Toast.show(context, 'Rollenänderung konnte nicht gespeichert werden');
    } finally {
      if (mounted) {
        setState(() {
          _updatingMemberUserId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final ownRole = context.watch<GroupRoleProvider>().roleForGroup(
      widget.groupId,
    );
    final canManageMembers = ownRole == GroupMemberRole.wart;
    final sortedMembers = _sortedMembers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitgliederübersicht'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.sort_by_alpha,
              color: _sortOption == SortOption.alphabet
                  ? Colors.white
                  : Colors.white54,
            ),
            onPressed: () => setState(() => _sortOption = SortOption.alphabet),
          ),
          IconButton(
            icon: Icon(
              Icons.local_bar,
              color: _sortOption == SortOption.strichCount
                  ? Colors.white
                  : Colors.white54,
            ),
            onPressed: () =>
                setState(() => _sortOption = SortOption.strichCount),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadErrorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48),
                    const SizedBox(height: 16),
                    Text(_loadErrorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadMembers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut laden'),
                    ),
                  ],
                ),
              ),
            )
          : sortedMembers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Keine Mitglieder vorhanden'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loadMembers,
                    child: const Text('Erneut laden'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadMembers,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                itemCount: sortedMembers.length,
                itemBuilder: (context, index) {
                  final member = sortedMembers[index];
                  final strichLabel = _strichLabel(member.strichCount);
                  final showWartBadge = member.role == GroupMemberRole.wart;
                  final showMemberMenu = canManageMembers;
                  final isUpdatingMember =
                      _updatingMemberUserId == member.userId;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.person),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (showWartBadge) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.verified_user,
                                          size: 14,
                                          color: theme
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Bierlistenwart',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .colorScheme
                                                .onPrimaryContainer,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 72,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  member.strichCount.toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  strichLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.hintColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (showMemberMenu) ...[
                            const SizedBox(width: 8),
                            isUpdatingMember
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : PopupMenuButton<_MemberAction>(
                                    tooltip: 'Mitglied verwalten',
                                    onSelected: (action) =>
                                        _handleMemberAction(member, action),
                                    itemBuilder: (context) {
                                      final items =
                                          <PopupMenuEntry<_MemberAction>>[];
                                      if (member.role == GroupMemberRole.wart) {
                                        items.add(
                                          const PopupMenuItem<_MemberAction>(
                                            value: _MemberAction.demoteToMember,
                                            child: Text('Als Mitglied setzen'),
                                          ),
                                        );
                                      } else {
                                        items.add(
                                          const PopupMenuItem<_MemberAction>(
                                            value: _MemberAction.promoteToWart,
                                            child: Text(
                                              'Zum Bierlistenwart machen',
                                            ),
                                          ),
                                        );
                                      }
                                      return items;
                                    },
                                  ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

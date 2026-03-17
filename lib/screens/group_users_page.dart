import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group_member.dart';
import '../providers/auth_provider.dart';
import '../services/connectivity_service.dart';
import '../services/group_api_service.dart';
import '../services/group_member_cache_service.dart';
import '../services/http_service.dart';

enum SortOption { alphabet, strichCount }

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
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final userEmail = context.read<AuthProvider>().userEmail;

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

    try {
      if (await ConnectivityService.isOnline()) {
        final members = await GroupMemberCacheService.refreshGroupMembers(
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
      await _loadCachedMembers(userEmail, fallbackErrorMessage: e.message);
    } on TimeoutException {
      await _loadCachedMembers(
        userEmail,
        fallbackErrorMessage: 'Mitglieder konnten nicht geladen werden',
      );
    } catch (_) {
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
    final cachedMembers = await GroupMemberCacheService.getGroupMembers(
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

  String _roleLabel(GroupMemberRole role) {
    switch (role) {
      case GroupMemberRole.admin:
        return 'Bierlistenwart';
      case GroupMemberRole.member:
        return 'Mitglied';
      case GroupMemberRole.unknown:
        return 'Unbekannte Rolle';
    }
  }

  Color _roleBackgroundColor(ThemeData theme, GroupMemberRole role) {
    switch (role) {
      case GroupMemberRole.admin:
        return theme.colorScheme.primaryContainer;
      case GroupMemberRole.member:
        return theme.colorScheme.surfaceContainerHighest;
      case GroupMemberRole.unknown:
        return theme.colorScheme.errorContainer;
    }
  }

  Color _roleForegroundColor(ThemeData theme, GroupMemberRole role) {
    switch (role) {
      case GroupMemberRole.admin:
        return theme.colorScheme.onPrimaryContainer;
      case GroupMemberRole.member:
        return theme.colorScheme.onSurfaceVariant;
      case GroupMemberRole.unknown:
        return theme.colorScheme.onErrorContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
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
                  final roleLabel = _roleLabel(member.role);
                  final roleBackgroundColor = _roleBackgroundColor(
                    theme,
                    member.role,
                  );
                  final roleForegroundColor = _roleForegroundColor(
                    theme,
                    member.role,
                  );

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
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: roleBackgroundColor,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: roleForegroundColor,
                                    ),
                                  ),
                                ),
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

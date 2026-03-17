import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_role_cache_service.dart';
import 'package:flutter/material.dart';

class GroupRoleProvider with ChangeNotifier {
  final Map<int, GroupMemberRole> _rolesByGroupId = {};
  final Map<int, bool> _isLoadingByGroupId = {};

  GroupMemberRole? roleForGroup(int groupId) => _rolesByGroupId[groupId];

  bool isLoadingForGroup(int groupId) => _isLoadingByGroupId[groupId] ?? false;

  Future<void> loadRole(
    String userEmail,
    int groupId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _rolesByGroupId.containsKey(groupId)) {
      return;
    }

    _setLoading(groupId, true);

    try {
      final storedRole = await GroupRoleCacheService.getGroupRole(
        userEmail,
        groupId,
      );
      if (storedRole != null) {
        _setRole(groupId, storedRole);
      }

      if (!await ConnectivityService.isOnline()) {
        return;
      }

      final freshRole = await GroupRoleCacheService.refreshGroupRole(
        userEmail,
        groupId,
      );
      _setRole(groupId, freshRole);
    } catch (e) {
      debugPrint('loadRole Fehler fuer Gruppe $groupId: $e');
    } finally {
      _setLoading(groupId, false);
    }
  }

  Future<void> refreshRole(String userEmail, int groupId) {
    return loadRole(userEmail, groupId, forceRefresh: true);
  }

  void clear() {
    if (_rolesByGroupId.isEmpty && _isLoadingByGroupId.isEmpty) {
      return;
    }

    _rolesByGroupId.clear();
    _isLoadingByGroupId.clear();
    notifyListeners();
  }

  void _setRole(int groupId, GroupMemberRole role) {
    if (_rolesByGroupId[groupId] == role) {
      return;
    }

    _rolesByGroupId[groupId] = role;
    notifyListeners();
  }

  void _setLoading(int groupId, bool isLoading) {
    if (_isLoadingByGroupId[groupId] == isLoading) {
      return;
    }

    _isLoadingByGroupId[groupId] = isLoading;
    notifyListeners();
  }
}

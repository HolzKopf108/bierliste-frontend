import 'dart:async';

import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/group_role_cache_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:hive/hive.dart';

class OfflineGroupUsersActionResult {
  final List<GroupMember> members;
  final bool hasPendingSync;
  final String? errorMessage;

  const OfflineGroupUsersActionResult({
    required this.members,
    required this.hasPendingSync,
    this.errorMessage,
  });
}

class OfflineGroupUsersService {
  static const _boxName = 'group_member_cache';
  static const _requestTimeout = Duration(seconds: 5);

  static Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    } else {
      return Hive.openBox(_boxName);
    }
  }

  static Future<void> saveGroupMembers(
    String userEmail,
    int groupId,
    List<GroupMember> members,
  ) async {
    final box = await _openBox();
    await box.put(
      _groupMembersKey(userEmail, groupId),
      members.map((member) => member.toJson()).toList(),
    );
  }

  static Future<List<GroupMember>?> getGroupMembers(
    String userEmail,
    int groupId,
  ) async {
    final box = await _openBox();
    final rawList = box.get(_groupMembersKey(userEmail, groupId));
    if (rawList is! List) {
      return null;
    }

    try {
      return rawList.map<GroupMember>((entry) {
        if (entry is! Map) {
          throw const FormatException('Ungültiger Cache-Eintrag');
        }

        return GroupMember.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
    } catch (_) {
      await box.delete(_groupMembersKey(userEmail, groupId));
      return null;
    }
  }

  static Future<List<GroupMember>> refreshGroupMembers(
    String userEmail,
    int groupId, {
    Duration timeout = _requestTimeout,
  }) async {
    final members = await GroupApiService()
        .fetchGroupMembers(groupId)
        .timeout(timeout);
    await saveGroupMembers(userEmail, groupId, members);
    return members;
  }

  static Future<bool> syncGroupMembersInBackground(
    String userEmail,
    Iterable<int> groupIds, {
    Duration timeout = _requestTimeout,
  }) async {
    if (!await ConnectivityService.isOnline()) {
      return false;
    }

    try {
      for (final groupId in groupIds) {
        try {
          await refreshGroupMembers(userEmail, groupId, timeout: timeout);
        } on UnauthorizedException {
          rethrow;
        } catch (_) {}
      }

      return true;
    } on UnauthorizedException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  static Future<OfflineGroupUsersActionResult> promoteMember(
    String userEmail,
    int groupId,
    GroupMember member,
  ) async {
    final operation = await _queueRoleChange(
      userEmail,
      groupId,
      member,
      targetRole: GroupMemberRole.wart,
      operationType: PendingSyncOperation.promoteGroupMember,
    );
    return _syncQueuedRoleChangeIfPossible(
      userEmail,
      groupId,
      operation,
      fallbackErrorMessage:
          'Mitglied konnte nicht zum Bierlistenwart gemacht werden',
    );
  }

  static Future<OfflineGroupUsersActionResult> demoteMember(
    String userEmail,
    int groupId,
    GroupMember member,
  ) async {
    final operation = await _queueRoleChange(
      userEmail,
      groupId,
      member,
      targetRole: GroupMemberRole.member,
      operationType: PendingSyncOperation.demoteGroupMember,
    );
    return _syncQueuedRoleChangeIfPossible(
      userEmail,
      groupId,
      operation,
      fallbackErrorMessage: 'Rolle konnte nicht aktualisiert werden',
    );
  }

  static Future<bool> syncPendingOperations(
    String userEmail, {
    int? groupId,
  }) async {
    final allOperations = await PendingSyncQueueService.getOperations(
      userEmail,
    );
    final syncableOperations = allOperations.where((operation) {
      if (operation.domain != PendingSyncOperation.domainGroupUsers) {
        return false;
      }
      if (!operation.isReadyForSync) {
        return false;
      }
      if (groupId != null && operation.groupId != groupId) {
        return false;
      }
      return true;
    }).toList();

    if (syncableOperations.isEmpty) {
      return true;
    }

    var allSuccessful = true;
    var operations = List<PendingSyncOperation>.from(allOperations);

    for (final operation in syncableOperations) {
      try {
        if (operation.operationType ==
            PendingSyncOperation.promoteGroupMember) {
          final updatedMember = await GroupApiService().promoteGroupMember(
            operation.groupId,
            _targetUserId(operation),
          );
          await _mergeUpdatedMember(
            userEmail,
            operation.groupId,
            updatedMember,
          );
        } else if (operation.operationType ==
            PendingSyncOperation.demoteGroupMember) {
          final updatedMember = await GroupApiService().demoteGroupMember(
            operation.groupId,
            _targetUserId(operation),
          );
          await _mergeUpdatedMember(
            userEmail,
            operation.groupId,
            updatedMember,
          );
        } else {
          continue;
        }

        try {
          await GroupRoleCacheService.refreshGroupRole(
            userEmail,
            operation.groupId,
          );
        } catch (_) {}

        operations.removeWhere((entry) => entry.id == operation.id);
        await PendingSyncQueueService.saveOperations(userEmail, operations);
      } on UnauthorizedException {
        rethrow;
      } on GroupApiException catch (e) {
        allSuccessful = false;
        if (_isPermanentFailure(e.statusCode)) {
          operations.removeWhere((entry) => entry.id == operation.id);
          await PendingSyncQueueService.saveOperations(userEmail, operations);
          try {
            await refreshGroupMembers(userEmail, operation.groupId);
          } catch (_) {}
          try {
            await GroupRoleCacheService.refreshGroupRole(
              userEmail,
              operation.groupId,
            );
          } catch (_) {}
        } else {
          operations = _replaceOperation(
            operations,
            PendingSyncQueueService.scheduleRetry(operation),
          );
          await PendingSyncQueueService.saveOperations(userEmail, operations);
        }
      } catch (_) {
        allSuccessful = false;
        operations = _replaceOperation(
          operations,
          PendingSyncQueueService.scheduleRetry(operation),
        );
        await PendingSyncQueueService.saveOperations(userEmail, operations);
      }
    }

    return allSuccessful;
  }

  static Future<PendingSyncOperation> _queueRoleChange(
    String userEmail,
    int groupId,
    GroupMember member, {
    required GroupMemberRole targetRole,
    required String operationType,
  }) async {
    await _replaceMemberRole(
      userEmail,
      groupId,
      member.copyWith(role: targetRole),
    );

    final operation = PendingSyncQueueService.createOperation(
      userEmail: userEmail,
      domain: PendingSyncOperation.domainGroupUsers,
      operationType: operationType,
      groupId: groupId,
      payload: {'targetUserId': member.userId},
    );
    await PendingSyncQueueService.addOperation(operation);
    return operation;
  }

  static Future<OfflineGroupUsersActionResult> _syncQueuedRoleChangeIfPossible(
    String userEmail,
    int groupId,
    PendingSyncOperation operation, {
    required String fallbackErrorMessage,
  }) async {
    var members = (await getGroupMembers(userEmail, groupId)) ?? [];

    if (!await ConnectivityService.isOnline()) {
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: true,
      );
    }

    try {
      final updatedMember =
          operation.operationType == PendingSyncOperation.promoteGroupMember
          ? await GroupApiService().promoteGroupMember(
              groupId,
              _targetUserId(operation),
            )
          : await GroupApiService().demoteGroupMember(
              groupId,
              _targetUserId(operation),
            );

      await _mergeUpdatedMember(userEmail, groupId, updatedMember);
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      try {
        await GroupRoleCacheService.refreshGroupRole(userEmail, groupId);
      } catch (_) {}

      members = (await getGroupMembers(userEmail, groupId)) ?? members;
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        try {
          members = await refreshGroupMembers(userEmail, groupId);
        } catch (_) {
          members = (await getGroupMembers(userEmail, groupId)) ?? members;
        }
        try {
          await GroupRoleCacheService.refreshGroupRole(userEmail, groupId);
        } catch (_) {}

        return OfflineGroupUsersActionResult(
          members: members,
          hasPendingSync: false,
          errorMessage: _friendlyActionError(e, fallbackErrorMessage),
        );
      }

      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: true,
      );
    } catch (_) {
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: true,
      );
    }
  }

  static Future<void> _replaceMemberRole(
    String userEmail,
    int groupId,
    GroupMember updatedMember,
  ) async {
    final members = (await getGroupMembers(userEmail, groupId)) ?? [];
    var memberFound = false;
    final updatedMembers = members.map((member) {
      if (member.userId != updatedMember.userId) {
        return member;
      }

      memberFound = true;
      return updatedMember;
    }).toList();
    if (!memberFound) {
      updatedMembers.add(updatedMember);
    }
    await saveGroupMembers(userEmail, groupId, updatedMembers);
  }

  static Future<void> _mergeUpdatedMember(
    String userEmail,
    int groupId,
    GroupMember updatedMember,
  ) async {
    final members = (await getGroupMembers(userEmail, groupId)) ?? [];
    var memberFound = false;
    final updatedMembers = members.map((member) {
      if (member.userId != updatedMember.userId) {
        return member;
      }

      memberFound = true;
      return updatedMember;
    }).toList();

    if (!memberFound) {
      updatedMembers.add(updatedMember);
    }

    await saveGroupMembers(userEmail, groupId, updatedMembers);
  }

  static List<PendingSyncOperation> _replaceOperation(
    List<PendingSyncOperation> operations,
    PendingSyncOperation updatedOperation,
  ) {
    return operations.map((operation) {
      if (operation.id != updatedOperation.id) {
        return operation;
      }

      return updatedOperation;
    }).toList();
  }

  static int _targetUserId(PendingSyncOperation operation) {
    final rawValue = operation.payload['targetUserId'];
    if (rawValue is int) {
      return rawValue;
    }

    if (rawValue is num) {
      return rawValue.toInt();
    }

    return int.parse(rawValue.toString());
  }

  static bool _isPermanentFailure(int? statusCode) {
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }

  static String _friendlyActionError(
    GroupApiException exception,
    String fallbackMessage,
  ) {
    switch (exception.statusCode) {
      case 403:
        return 'Du darfst diese Aktion nicht ausführen';
      case 404:
        return 'Mitglied wurde nicht gefunden';
      default:
        final message = exception.message.trim();
        if (message.isNotEmpty) {
          return message;
        }
        return fallbackMessage;
    }
  }

  static String _groupMembersKey(String userEmail, int groupId) {
    return 'group_members_cache_${userEmail}_$groupId';
  }
}

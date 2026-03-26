import 'dart:async';

import 'package:bierliste/models/confirmed_counter_increment.dart';
import 'package:bierliste/models/counter_increment_result.dart';
import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/group_settlement_result.dart';
import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:bierliste/services/connectivity_service.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/group_counter_api_service.dart';
import 'package:bierliste/services/group_role_cache_service.dart';
import 'package:bierliste/services/group_settlement_api_service.dart';
import 'package:bierliste/services/http_service.dart';
import 'package:bierliste/services/offline_strich_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:bierliste/services/sync_debug_service.dart';
import 'package:hive/hive.dart';

class OfflineGroupUsersActionResult {
  final List<GroupMember> members;
  final bool hasPendingSync;
  final bool shouldReloadUi;
  final String? errorMessage;
  final String? localOperationId;

  const OfflineGroupUsersActionResult({
    required this.members,
    required this.hasPendingSync,
    this.shouldReloadUi = false,
    this.errorMessage,
    this.localOperationId,
  });
}

class OfflineGroupUsersService {
  static const _boxName = 'group_member_cache';
  static const _requestTimeout = Duration(seconds: 5);
  static const _moneySettlementTolerance = 0.0001;

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

  static Future<void> clearGroupMembers(String userEmail, int groupId) async {
    final box = await _openBox();
    await box.delete(_groupMembersKey(userEmail, groupId));
  }

  static Future<List<GroupMember>> refreshGroupMembers(
    String userEmail,
    int groupId, {
    Duration timeout = _requestTimeout,
  }) async {
    final backendMembers = await GroupApiService()
        .fetchGroupMembers(groupId)
        .timeout(timeout);
    final effectiveMembers = await _applyPendingOperationsOverlay(
      userEmail,
      groupId,
      backendMembers,
    );
    await saveGroupMembers(userEmail, groupId, effectiveMembers);
    return effectiveMembers;
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
      fallbackErrorMessage: 'Bierlistenwart konnte nicht herabgestuft werden',
    );
  }

  static Future<OfflineGroupUsersActionResult> removeMember(
    String userEmail,
    int groupId,
    GroupMember member,
  ) async {
    var members = await _currentMembers(userEmail, groupId);

    if (!await ConnectivityService.isOnline()) {
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        errorMessage: 'Keine Verbindung',
      );
    }

    try {
      await GroupApiService().removeMember(groupId, member.userId);
      try {
        await GroupRoleCacheService.refreshGroupRole(userEmail, groupId);
      } catch (_) {}

      try {
        members = await refreshGroupMembers(userEmail, groupId);
      } catch (_) {
        members = _removeMemberFromList(members, member.userId);
        await saveGroupMembers(userEmail, groupId, members);
      }

      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        try {
          members = await refreshGroupMembers(userEmail, groupId);
        } catch (_) {
          members = (await getGroupMembers(userEmail, groupId)) ?? members;
        }
        try {
          await GroupRoleCacheService.refreshGroupRole(userEmail, groupId);
        } catch (_) {}
      }

      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        shouldReloadUi: _shouldReloadUi(e.statusCode),
        errorMessage: _friendlyRemoveMemberError(e),
      );
    } catch (_) {
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        errorMessage: 'Mitglied konnte nicht entfernt werden',
      );
    }
  }

  static Future<OfflineGroupUsersActionResult> settleMemberMoney(
    String userEmail,
    int groupId,
    GroupMember member,
    double amount, {
    required double pricePerStrich,
    required bool allowArbitraryMoneySettlements,
    required bool affectsCurrentUser,
  }) async {
    if (amount <= 0) {
      final members = await _currentMembers(userEmail, groupId);
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        errorMessage: 'Ungültiger Betrag',
      );
    }

    final settlementStriche = calculateMoneySettlementStriche(
      amount,
      pricePerStrich,
      allowArbitraryMoneySettlements: allowArbitraryMoneySettlements,
    );
    if (settlementStriche == null) {
      final members = await _currentMembers(userEmail, groupId);
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        errorMessage:
            'Betrag muss ein Vielfaches von ${_formatMoney(pricePerStrich)} € sein',
      );
    }

    return _queueAndSyncSettlement(
      userEmail,
      groupId,
      member,
      operationType: PendingSyncOperation.settleGroupMemberMoney,
      amount: amount,
      localStrichDelta: -settlementStriche,
      affectsCurrentUser: affectsCurrentUser,
      fallbackErrorMessage: 'Geld konnte nicht abgezogen werden',
    );
  }

  static Future<OfflineGroupUsersActionResult> settleMemberStriche(
    String userEmail,
    int groupId,
    GroupMember member,
    int amount, {
    required bool affectsCurrentUser,
  }) async {
    if (amount <= 0) {
      final members = await _currentMembers(userEmail, groupId);
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        errorMessage: 'Ungültige Anzahl',
      );
    }

    return _queueAndSyncSettlement(
      userEmail,
      groupId,
      member,
      operationType: PendingSyncOperation.settleGroupMemberStriche,
      amount: amount,
      localStrichDelta: -amount,
      affectsCurrentUser: affectsCurrentUser,
      fallbackErrorMessage: 'Striche konnten nicht abgezogen werden',
    );
  }

  static Future<OfflineGroupUsersActionResult> incrementMemberCounter(
    String userEmail,
    int groupId,
    GroupMember member,
    int amount, {
    required bool affectsCurrentUser,
  }) async {
    if (amount <= 0) {
      final members = await _currentMembers(userEmail, groupId);
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: false,
        errorMessage: 'Ungültige Anzahl',
      );
    }

    return _queueAndSyncCounterIncrement(
      userEmail,
      groupId,
      member,
      amount,
      affectsCurrentUser: affectsCurrentUser,
      fallbackErrorMessage: 'Striche konnten nicht gespeichert werden',
    );
  }

  static Future<OfflineGroupUsersActionResult> undoMemberCounterIncrement(
    String userEmail,
    int groupId,
    GroupMember member,
    String localOperationId,
    int amount, {
    required bool affectsCurrentUser,
    required bool isSyncing,
  }) async {
    final members = await _currentMembers(userEmail, groupId);
    final confirmed = await OfflineStrichService.getConfirmedIncrement(
      userEmail,
      localOperationId,
      groupId: groupId,
    );
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    final existingUndoOperation = _findCounterUndoOperation(
      operations,
      localOperationId,
    );
    SyncDebugService.log(
      'OfflineGroupUsersService',
      'undo member counter requested',
      details: {
        'userEmail': userEmail,
        'groupId': groupId,
        'targetUserId': member.userId,
        'localOperationId': localOperationId,
        'amount': amount,
        'isSyncing': isSyncing,
        'hasConfirmed': confirmed != null,
        'hasExistingUndoOperation': existingUndoOperation != null,
        'operations': SyncDebugService.summarizeOperations(operations),
      },
    );

    if (existingUndoOperation != null) {
      return OfflineGroupUsersActionResult(
        members: members,
        hasPendingSync: true,
        localOperationId: localOperationId,
      );
    }

    if (confirmed != null) {
      if (_isUndoExpired(confirmed.undoExpiresAt)) {
        await OfflineStrichService.removeConfirmedIncrement(
          userEmail,
          groupId,
          localOperationId,
        );
        return OfflineGroupUsersActionResult(
          members: members,
          hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
            userEmail,
          ),
          errorMessage: 'Undo-Zeitfenster abgelaufen',
          localOperationId: localOperationId,
        );
      }

      return _queueAndSyncCounterUndo(
        userEmail,
        groupId,
        member,
        localOperationId,
        amount,
        affectsCurrentUser: affectsCurrentUser,
        confirmed: confirmed,
        isSyncing: isSyncing,
      );
    }

    final originalOperation = operations
        .cast<PendingSyncOperation?>()
        .firstWhere((operation) {
          return operation != null &&
              operation.id == localOperationId &&
              operation.domain == PendingSyncOperation.domainGroupUsers &&
              operation.operationType ==
                  PendingSyncOperation.incrementGroupMemberCounter &&
              operation.groupId == groupId;
        }, orElse: () => null);

    if (originalOperation != null && !isSyncing) {
      final updatedMembers = _applySettlementDeltaToMembers(
        members,
        member.userId,
        -amount,
        fallbackMember: member,
        addIfMissing: true,
      );
      await saveGroupMembers(userEmail, groupId, updatedMembers);
      await PendingSyncQueueService.removeOperations(userEmail, [
        originalOperation.id,
      ]);
      return OfflineGroupUsersActionResult(
        members: updatedMembers,
        hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
          userEmail,
        ),
        localOperationId: localOperationId,
      );
    }

    if (originalOperation != null) {
      return _queueAndSyncCounterUndo(
        userEmail,
        groupId,
        member,
        localOperationId,
        amount,
        affectsCurrentUser: affectsCurrentUser,
        isSyncing: true,
      );
    }

    return OfflineGroupUsersActionResult(
      members: members,
      hasPendingSync: await PendingSyncQueueService.hasPendingOperations(
        userEmail,
      ),
      errorMessage: 'Strich kann gerade nicht rückgängig gemacht werden',
      localOperationId: localOperationId,
    );
  }

  static int? calculateMoneySettlementStriche(
    double amount,
    double pricePerStrich, {
    required bool allowArbitraryMoneySettlements,
  }) {
    if (amount <= 0 || pricePerStrich <= 0) {
      return null;
    }

    final rawCount = amount / pricePerStrich;
    if (allowArbitraryMoneySettlements) {
      return rawCount.floor();
    }

    final roundedCount = rawCount.round();
    final diff = (rawCount - roundedCount).abs();
    if (diff > _moneySettlementTolerance) {
      return null;
    }

    return roundedCount;
  }

  static Future<bool> syncPendingOperations(
    String userEmail, {
    int? groupId,
  }) async {
    var operations = await PendingSyncQueueService.getOperations(userEmail);
    operations = await _removeLocallyUndonePendingCounterIncrements(
      userEmail,
      operations,
      groupId: groupId,
    );
    final syncableOperations = operations.where((operation) {
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

    SyncDebugService.log(
      'OfflineGroupUsersService',
      'group user sync started',
      details: {
        'userEmail': userEmail,
        'groupId': groupId,
        'operations': SyncDebugService.summarizeOperations(syncableOperations),
      },
    );

    var allSuccessful = true;

    for (final operation in syncableOperations) {
      if (!operations.any((entry) => entry.id == operation.id)) {
        continue;
      }

      try {
        if (operation.operationType ==
            PendingSyncOperation.promoteGroupMember) {
          final updatedMember = await GroupApiService().promoteGroupMember(
            operation.groupId,
            _targetUserId(operation),
          );
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          if (_hasPendingGroupUserOperationsInList(
            operations,
            operation.groupId,
          )) {
            await refreshGroupMembers(userEmail, operation.groupId);
          } else {
            await _mergeUpdatedMember(
              userEmail,
              operation.groupId,
              updatedMember,
            );
          }
          try {
            await GroupRoleCacheService.refreshGroupRole(
              userEmail,
              operation.groupId,
            );
          } catch (_) {}
        } else if (operation.operationType ==
            PendingSyncOperation.demoteGroupMember) {
          final updatedMember = await GroupApiService().demoteGroupMember(
            operation.groupId,
            _targetUserId(operation),
          );
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          if (_hasPendingGroupUserOperationsInList(
            operations,
            operation.groupId,
          )) {
            await refreshGroupMembers(userEmail, operation.groupId);
          } else {
            await _mergeUpdatedMember(
              userEmail,
              operation.groupId,
              updatedMember,
            );
          }
          try {
            await GroupRoleCacheService.refreshGroupRole(
              userEmail,
              operation.groupId,
            );
          } catch (_) {}
        } else if (_isSettlementOperation(operation)) {
          final settlement = await _syncSettlementOperation(operation);
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          final updatedMembers = await _membersAfterSuccessfulSettlement(
            userEmail,
            operation.groupId,
            _targetUserId(operation),
            settlement,
          );
          final resolvedCount = _resolvedCountForMembers(
            updatedMembers,
            _targetUserId(operation),
            settlement,
          );
          if (_affectsCurrentUser(operation) && resolvedCount != null) {
            await OfflineStrichService.saveLastOnlineCounter(
              userEmail,
              operation.groupId,
              resolvedCount,
            );
          }
        } else if (_isCounterIncrementOperation(operation)) {
          SyncDebugService.log(
            'OfflineGroupUsersService',
            'syncing member counter increment',
            details: {
              'operationId': operation.id,
              'groupId': operation.groupId,
              'targetUserId': _targetUserId(operation),
              'amount': _intAmount(operation),
            },
          );
          final increment = await _syncCounterIncrementOperation(operation);
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          await OfflineStrichService.saveConfirmedIncrement(
            userEmail,
            ConfirmedCounterIncrement(
              localOperationId: operation.id,
              groupId: operation.groupId,
              amount: _intAmount(operation),
              incrementRequestId: increment.incrementRequestId,
              undoExpiresAt: increment.undoExpiresAt,
              targetUserId: _targetUserId(operation),
              targetUsername: _targetUsername(operation),
              affectsCurrentUser: _affectsCurrentUser(operation),
            ),
          );
          final updatedMembers = await _membersAfterSuccessfulCounterIncrement(
            userEmail,
            operation.groupId,
            _targetUserId(operation),
            increment.count,
          );
          final effectiveCount = _resolvedCountFromMembers(
            updatedMembers,
            _targetUserId(operation),
            fallbackCount: increment.count,
          );
          if (_affectsCurrentUser(operation) && effectiveCount != null) {
            await OfflineStrichService.saveLastOnlineCounter(
              userEmail,
              operation.groupId,
              effectiveCount,
            );
          }
          SyncDebugService.log(
            'OfflineGroupUsersService',
            'member counter increment synced',
            details: {
              'operationId': operation.id,
              'groupId': operation.groupId,
              'targetUserId': _targetUserId(operation),
              'count': increment.count,
              'incrementRequestId': increment.incrementRequestId,
            },
          );
        } else if (_isCounterUndoOperation(operation)) {
          SyncDebugService.log(
            'OfflineGroupUsersService',
            'syncing member counter undo',
            details: {
              'operationId': operation.id,
              'groupId': operation.groupId,
              'targetUserId': _targetUserId(operation),
              'localOperationId': _localOperationId(operation),
            },
          );
          final syncResult = await _syncCounterUndoOperation(
            userEmail,
            operation,
            operations,
          );
          operations = syncResult.operations;
          if (!syncResult.successful) {
            allSuccessful = false;
          }
        } else {
          continue;
        }
      } on UnauthorizedException {
        rethrow;
      } on GroupApiException catch (e) {
        allSuccessful = false;
        if (_isPermanentFailure(e.statusCode)) {
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
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
          await PendingSyncQueueService.replaceOperation(
            userEmail,
            PendingSyncQueueService.scheduleRetry(operation),
          );
          operations = await PendingSyncQueueService.getOperations(userEmail);
        }
      } on GroupSettlementApiException catch (e) {
        allSuccessful = false;
        if (_isPermanentFailure(e.statusCode)) {
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          try {
            await refreshGroupMembers(userEmail, operation.groupId);
          } catch (_) {}
        } else {
          await PendingSyncQueueService.replaceOperation(
            userEmail,
            PendingSyncQueueService.scheduleRetry(operation),
          );
          operations = await PendingSyncQueueService.getOperations(userEmail);
        }
      } on GroupCounterApiException catch (e) {
        allSuccessful = false;
        SyncDebugService.log(
          'OfflineGroupUsersService',
          'group user counter sync failed',
          details: {
            'operationId': operation.id,
            'operationType': operation.operationType,
            'groupId': operation.groupId,
            'statusCode': e.statusCode,
            'message': e.message,
          },
        );
        if (_isPermanentFailure(e.statusCode)) {
          await PendingSyncQueueService.removeOperations(userEmail, [
            operation.id,
          ]);
          operations = await PendingSyncQueueService.getOperations(userEmail);
          try {
            await refreshGroupMembers(userEmail, operation.groupId);
          } catch (_) {}
        } else {
          await PendingSyncQueueService.replaceOperation(
            userEmail,
            PendingSyncQueueService.scheduleRetry(operation),
          );
          operations = await PendingSyncQueueService.getOperations(userEmail);
        }
      } on TimeoutException {
        allSuccessful = false;
        SyncDebugService.log(
          'OfflineGroupUsersService',
          'group user sync timed out',
          details: {
            'operationId': operation.id,
            'operationType': operation.operationType,
            'groupId': operation.groupId,
          },
        );
        await PendingSyncQueueService.replaceOperation(
          userEmail,
          PendingSyncQueueService.scheduleRetry(operation),
        );
        operations = await PendingSyncQueueService.getOperations(userEmail);
      } catch (_) {
        allSuccessful = false;
        SyncDebugService.log(
          'OfflineGroupUsersService',
          'group user sync failed with unexpected error',
          details: {
            'operationId': operation.id,
            'operationType': operation.operationType,
            'groupId': operation.groupId,
          },
        );
        await PendingSyncQueueService.replaceOperation(
          userEmail,
          PendingSyncQueueService.scheduleRetry(operation),
        );
        operations = await PendingSyncQueueService.getOperations(userEmail);
      }
    }

    SyncDebugService.log(
      'OfflineGroupUsersService',
      'group user sync finished',
      details: {
        'userEmail': userEmail,
        'groupId': groupId,
        'success': allSuccessful,
        'remainingOperations': SyncDebugService.summarizeOperations(operations),
      },
    );

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

      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      if (await _hasPendingGroupUserOperations(userEmail, groupId)) {
        await refreshGroupMembers(userEmail, groupId);
      } else {
        await _mergeUpdatedMember(userEmail, groupId, updatedMember);
      }
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
          shouldReloadUi: _shouldReloadUi(e.statusCode),
          errorMessage: _friendlyRoleActionError(
            e,
            operation,
            fallbackErrorMessage,
          ),
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

  static Future<OfflineGroupUsersActionResult> _queueAndSyncCounterIncrement(
    String userEmail,
    int groupId,
    GroupMember member,
    int amount, {
    required bool affectsCurrentUser,
    required String fallbackErrorMessage,
  }) async {
    final previousMembers = await _currentMembers(userEmail, groupId);
    final optimisticMembers = _applySettlementDeltaToMembers(
      previousMembers,
      member.userId,
      amount,
      fallbackMember: member,
      addIfMissing: true,
    );
    await saveGroupMembers(userEmail, groupId, optimisticMembers);

    final operation = PendingSyncQueueService.createOperation(
      userEmail: userEmail,
      domain: PendingSyncOperation.domainGroupUsers,
      operationType: PendingSyncOperation.incrementGroupMemberCounter,
      groupId: groupId,
      payload: {
        'targetUserId': member.userId,
        'targetUsername': member.username,
        'amount': amount,
        'localStrichDelta': amount,
        'affectsCurrentUser': affectsCurrentUser,
      },
    );
    await PendingSyncQueueService.addOperation(operation);
    SyncDebugService.log(
      'OfflineGroupUsersService',
      'member counter increment queued',
      details: {
        'userEmail': userEmail,
        'groupId': groupId,
        'targetUserId': member.userId,
        'operationId': operation.id,
        'amount': amount,
      },
    );

    if (!await ConnectivityService.isOnline()) {
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
        localOperationId: operation.id,
      );
    }

    try {
      final increment = await _syncCounterIncrementOperation(operation);
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      await OfflineStrichService.saveConfirmedIncrement(
        userEmail,
        ConfirmedCounterIncrement(
          localOperationId: operation.id,
          groupId: groupId,
          amount: amount,
          incrementRequestId: increment.incrementRequestId,
          undoExpiresAt: increment.undoExpiresAt,
          targetUserId: member.userId,
          targetUsername: member.username,
          affectsCurrentUser: affectsCurrentUser,
        ),
      );
      final syncedMembers = await _membersAfterSuccessfulCounterIncrement(
        userEmail,
        groupId,
        member.userId,
        increment.count,
      );
      final effectiveCount = _resolvedCountFromMembers(
        syncedMembers,
        member.userId,
        fallbackCount: increment.count,
      );
      if (affectsCurrentUser && effectiveCount != null) {
        await OfflineStrichService.saveLastOnlineCounter(
          userEmail,
          groupId,
          effectiveCount,
        );
      }
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter increment synced immediately',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'targetUserId': member.userId,
          'operationId': operation.id,
          'count': increment.count,
          'incrementRequestId': increment.incrementRequestId,
        },
      );

      return OfflineGroupUsersActionResult(
        members: syncedMembers,
        hasPendingSync: false,
        localOperationId: operation.id,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupCounterApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        final restoredMembers = await _restoreMembersAfterPermanentFailure(
          userEmail,
          groupId,
          previousMembers,
        );
        return OfflineGroupUsersActionResult(
          members: restoredMembers,
          hasPendingSync: false,
          shouldReloadUi: _shouldReloadUi(e.statusCode),
          errorMessage: _friendlyCounterIncrementError(
            e,
            fallbackMessage: fallbackErrorMessage,
          ),
          localOperationId: operation.id,
        );
      }

      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter increment kept queued after immediate sync failure',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'targetUserId': member.userId,
          'operationId': operation.id,
          'statusCode': e.statusCode,
          'message': e.message,
        },
      );

      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
        localOperationId: operation.id,
      );
    } catch (_) {
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
        localOperationId: operation.id,
      );
    }
  }

  static Future<OfflineGroupUsersActionResult> _queueAndSyncCounterUndo(
    String userEmail,
    int groupId,
    GroupMember member,
    String localOperationId,
    int amount, {
    required bool affectsCurrentUser,
    required bool isSyncing,
    ConfirmedCounterIncrement? confirmed,
  }) async {
    final previousMembers = await _currentMembers(userEmail, groupId);
    final optimisticMembers = _applySettlementDeltaToMembers(
      previousMembers,
      member.userId,
      -amount,
      fallbackMember: member,
      addIfMissing: true,
    );
    await saveGroupMembers(userEmail, groupId, optimisticMembers);

    final operation = PendingSyncQueueService.createOperation(
      userEmail: userEmail,
      domain: PendingSyncOperation.domainGroupUsers,
      operationType: PendingSyncOperation.undoGroupMemberCounterIncrement,
      groupId: groupId,
      payload: {
        'localOperationId': localOperationId,
        'targetUserId': member.userId,
        'targetUsername': member.username,
        'amount': amount,
        'localStrichDelta': -amount,
        'affectsCurrentUser': affectsCurrentUser,
        if (confirmed != null)
          'incrementRequestId': confirmed.incrementRequestId,
        if (confirmed != null)
          'undoExpiresAt': confirmed.undoExpiresAt.toUtc().toIso8601String(),
      },
    );
    await PendingSyncQueueService.addOperation(operation);
    SyncDebugService.log(
      'OfflineGroupUsersService',
      'member counter undo queued',
      details: {
        'userEmail': userEmail,
        'groupId': groupId,
        'targetUserId': member.userId,
        'operationId': operation.id,
        'localOperationId': localOperationId,
        'amount': amount,
        'isSyncing': isSyncing,
        'hasConfirmed': confirmed != null,
      },
    );

    final isOnline = await ConnectivityService.isOnline();
    if (!isOnline || isSyncing || confirmed == null) {
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter undo left in queue instead of direct sync',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'targetUserId': member.userId,
          'operationId': operation.id,
          'localOperationId': localOperationId,
          'isOnline': isOnline,
          'isSyncing': isSyncing,
          'hasConfirmed': confirmed != null,
        },
      );
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
        localOperationId: localOperationId,
      );
    }

    try {
      final undo = await GroupCounterApiService().undoCounterIncrement(
        groupId,
        confirmed.incrementRequestId,
      );
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      await OfflineStrichService.removeConfirmedIncrement(
        userEmail,
        groupId,
        localOperationId,
      );
      final syncedMembers = await _membersAfterSuccessfulCounterIncrement(
        userEmail,
        groupId,
        member.userId,
        undo.count,
      );
      final effectiveCount = _resolvedCountFromMembers(
        syncedMembers,
        member.userId,
        fallbackCount: undo.count,
      );
      if (affectsCurrentUser && effectiveCount != null) {
        await OfflineStrichService.saveLastOnlineCounter(
          userEmail,
          groupId,
          effectiveCount,
        );
      }
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter undo synced immediately',
        details: {
          'userEmail': userEmail,
          'groupId': groupId,
          'targetUserId': member.userId,
          'operationId': operation.id,
          'localOperationId': localOperationId,
          'count': undo.count,
          'incrementRequestId': confirmed.incrementRequestId,
        },
      );

      return OfflineGroupUsersActionResult(
        members: syncedMembers,
        hasPendingSync: false,
        localOperationId: localOperationId,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupCounterApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        await OfflineStrichService.removeConfirmedIncrement(
          userEmail,
          groupId,
          localOperationId,
        );
        final restoredMembers = await _restoreMembersAfterPermanentFailure(
          userEmail,
          groupId,
          previousMembers,
        );
        return OfflineGroupUsersActionResult(
          members: restoredMembers,
          hasPendingSync: false,
          shouldReloadUi: _shouldReloadUi(e.statusCode),
          errorMessage: _friendlyCounterUndoError(e),
          localOperationId: localOperationId,
        );
      }

      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
        localOperationId: localOperationId,
      );
    } catch (_) {
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
        localOperationId: localOperationId,
      );
    }
  }

  static Future<OfflineGroupUsersActionResult> _queueAndSyncSettlement(
    String userEmail,
    int groupId,
    GroupMember member, {
    required String operationType,
    required num amount,
    required int localStrichDelta,
    required bool affectsCurrentUser,
    required String fallbackErrorMessage,
  }) async {
    final previousMembers = await _currentMembers(userEmail, groupId);
    final optimisticMembers = _applySettlementDeltaToMembers(
      previousMembers,
      member.userId,
      localStrichDelta,
      fallbackMember: member,
      addIfMissing: true,
    );
    await saveGroupMembers(userEmail, groupId, optimisticMembers);

    final operation = PendingSyncQueueService.createOperation(
      userEmail: userEmail,
      domain: PendingSyncOperation.domainGroupUsers,
      operationType: operationType,
      groupId: groupId,
      payload: {
        'targetUserId': member.userId,
        'amount': amount,
        'localStrichDelta': localStrichDelta,
        'affectsCurrentUser': affectsCurrentUser,
      },
    );
    await PendingSyncQueueService.addOperation(operation);

    if (!await ConnectivityService.isOnline()) {
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
      );
    }

    try {
      final settlement = await _syncSettlementOperation(operation);
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      final syncedMembers = await _membersAfterSuccessfulSettlement(
        userEmail,
        groupId,
        member.userId,
        settlement,
      );
      final resolvedCount = _resolvedCountForMembers(
        syncedMembers,
        member.userId,
        settlement,
      );
      if (affectsCurrentUser && resolvedCount != null) {
        await OfflineStrichService.saveLastOnlineCounter(
          userEmail,
          groupId,
          resolvedCount,
        );
      }

      return OfflineGroupUsersActionResult(
        members: syncedMembers,
        hasPendingSync: false,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupSettlementApiException catch (e) {
      if (_isPermanentFailure(e.statusCode)) {
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        final restoredMembers = await _restoreMembersAfterPermanentFailure(
          userEmail,
          groupId,
          previousMembers,
        );
        return OfflineGroupUsersActionResult(
          members: restoredMembers,
          hasPendingSync: false,
          shouldReloadUi: _shouldReloadUi(e.statusCode),
          errorMessage: _friendlySettlementError(
            e,
            operationType: operationType,
            fallbackMessage: fallbackErrorMessage,
          ),
        );
      }

      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
      );
    } on TimeoutException {
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
      );
    } catch (_) {
      return OfflineGroupUsersActionResult(
        members: optimisticMembers,
        hasPendingSync: true,
      );
    }
  }

  static Future<List<GroupMember>> _applySettlementResponse(
    String userEmail,
    int groupId,
    int targetUserId,
    GroupSettlementResult settlement,
  ) async {
    if (settlement.member != null) {
      await _mergeUpdatedMember(userEmail, groupId, settlement.member!);
      return (await getGroupMembers(userEmail, groupId)) ?? [];
    }

    final count = settlement.resolvedStrichCount;
    if (count == null) {
      throw const FormatException('Settlement ohne StrichCount');
    }

    return _applyResolvedStrichCount(userEmail, groupId, targetUserId, count);
  }

  static Future<List<GroupMember>> _applyResolvedStrichCount(
    String userEmail,
    int groupId,
    int targetUserId,
    int count,
  ) async {
    final members = await _currentMembers(userEmail, groupId);
    final updatedMembers = _setMemberStrichCount(
      members,
      targetUserId,
      count,
      addIfMissing: false,
    );
    await saveGroupMembers(userEmail, groupId, updatedMembers);
    return updatedMembers;
  }

  static Future<List<GroupMember>> _membersAfterSuccessfulSettlement(
    String userEmail,
    int groupId,
    int targetUserId,
    GroupSettlementResult settlement,
  ) async {
    if (await _hasPendingGroupUserOperations(userEmail, groupId)) {
      return refreshGroupMembers(userEmail, groupId);
    }

    return _applySettlementResponse(
      userEmail,
      groupId,
      targetUserId,
      settlement,
    );
  }

  static Future<List<GroupMember>> _membersAfterSuccessfulCounterIncrement(
    String userEmail,
    int groupId,
    int targetUserId,
    int count,
  ) async {
    if (await _hasPendingGroupUserOperations(userEmail, groupId)) {
      try {
        return await refreshGroupMembers(userEmail, groupId);
      } catch (e) {
        SyncDebugService.log(
          'OfflineGroupUsersService',
          'member refresh failed after successful counter update, falling back to local overlay',
          details: {
            'userEmail': userEmail,
            'groupId': groupId,
            'targetUserId': targetUserId,
            'count': count,
            'error': e.toString(),
          },
        );
        final resolvedMembers = await _applyResolvedStrichCount(
          userEmail,
          groupId,
          targetUserId,
          count,
        );
        final effectiveMembers = await _applyPendingOperationsOverlay(
          userEmail,
          groupId,
          resolvedMembers,
        );
        await saveGroupMembers(userEmail, groupId, effectiveMembers);
        return effectiveMembers;
      }
    }

    return _applyResolvedStrichCount(userEmail, groupId, targetUserId, count);
  }

  static Future<GroupSettlementResult> _syncSettlementOperation(
    PendingSyncOperation operation,
  ) {
    if (operation.operationType ==
        PendingSyncOperation.settleGroupMemberMoney) {
      return GroupSettlementApiService().settleMoney(
        operation.groupId,
        _targetUserId(operation),
        _moneyAmount(operation),
      );
    }

    if (operation.operationType ==
        PendingSyncOperation.settleGroupMemberStriche) {
      return GroupSettlementApiService().settleStriche(
        operation.groupId,
        _targetUserId(operation),
        _intAmount(operation),
      );
    }

    throw UnsupportedError(
      'Settlement-Operation ${operation.operationType} wird nicht unterstützt',
    );
  }

  static Future<CounterIncrementResult> _syncCounterIncrementOperation(
    PendingSyncOperation operation,
  ) async {
    return GroupCounterApiService().incrementGroupMemberCounter(
      operation.groupId,
      _targetUserId(operation),
      _intAmount(operation),
    );
  }

  static Future<_GroupUsersUndoSyncResult> _syncCounterUndoOperation(
    String userEmail,
    PendingSyncOperation operation,
    List<PendingSyncOperation> operations,
  ) async {
    final localOperationId = _localOperationId(operation);
    if (localOperationId == null || localOperationId.isEmpty) {
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return _GroupUsersUndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        true,
      );
    }

    final confirmed = await OfflineStrichService.getConfirmedIncrement(
      userEmail,
      localOperationId,
      groupId: operation.groupId,
    );
    if (confirmed == null) {
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter undo skipped because confirmed increment is missing',
        details: {
          'userEmail': userEmail,
          'groupId': operation.groupId,
          'operationId': operation.id,
          'localOperationId': localOperationId,
          'operations': SyncDebugService.summarizeOperations(operations),
        },
      );
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      return _GroupUsersUndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        true,
      );
    }

    final undoExpiresAt = _undoExpiresAt(operation, confirmed);
    if (_isUndoExpired(undoExpiresAt)) {
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter undo expired before sync',
        details: {
          'userEmail': userEmail,
          'groupId': operation.groupId,
          'operationId': operation.id,
          'localOperationId': localOperationId,
          'undoExpiresAt': undoExpiresAt.toIso8601String(),
        },
      );
      await OfflineStrichService.removeConfirmedIncrement(
        userEmail,
        operation.groupId,
        localOperationId,
      );
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      try {
        await refreshGroupMembers(userEmail, operation.groupId);
      } catch (_) {}
      return _GroupUsersUndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        false,
      );
    }

    try {
      final undo = await GroupCounterApiService().undoCounterIncrement(
        operation.groupId,
        confirmed.incrementRequestId,
      );
      await PendingSyncQueueService.removeOperations(userEmail, [operation.id]);
      await OfflineStrichService.removeConfirmedIncrement(
        userEmail,
        operation.groupId,
        localOperationId,
      );
      final updatedMembers = await _membersAfterSuccessfulCounterIncrement(
        userEmail,
        operation.groupId,
        _targetUserId(operation),
        undo.count,
      );
      final effectiveCount = _resolvedCountFromMembers(
        updatedMembers,
        _targetUserId(operation),
        fallbackCount: undo.count,
      );
      if (_affectsCurrentUser(operation) && effectiveCount != null) {
        await OfflineStrichService.saveLastOnlineCounter(
          userEmail,
          operation.groupId,
          effectiveCount,
        );
      }
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter undo synced',
        details: {
          'userEmail': userEmail,
          'groupId': operation.groupId,
          'operationId': operation.id,
          'localOperationId': localOperationId,
          'incrementRequestId': confirmed.incrementRequestId,
          'count': undo.count,
        },
      );
      return _GroupUsersUndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        true,
      );
    } on UnauthorizedException {
      rethrow;
    } on GroupCounterApiException catch (e) {
      SyncDebugService.log(
        'OfflineGroupUsersService',
        'member counter undo sync failed',
        details: {
          'userEmail': userEmail,
          'groupId': operation.groupId,
          'operationId': operation.id,
          'localOperationId': localOperationId,
          'statusCode': e.statusCode,
          'message': e.message,
        },
      );
      if (_isPermanentFailure(e.statusCode)) {
        await OfflineStrichService.removeConfirmedIncrement(
          userEmail,
          operation.groupId,
          localOperationId,
        );
        await PendingSyncQueueService.removeOperations(userEmail, [
          operation.id,
        ]);
        try {
          await refreshGroupMembers(userEmail, operation.groupId);
        } catch (_) {}
        return _GroupUsersUndoSyncResult(
          await PendingSyncQueueService.getOperations(userEmail),
          false,
        );
      }

      await PendingSyncQueueService.replaceOperation(
        userEmail,
        PendingSyncQueueService.scheduleUndoRetry(operation, undoExpiresAt),
      );
      return _GroupUsersUndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        false,
      );
    } catch (_) {
      await PendingSyncQueueService.replaceOperation(
        userEmail,
        PendingSyncQueueService.scheduleUndoRetry(operation, undoExpiresAt),
      );
      return _GroupUsersUndoSyncResult(
        await PendingSyncQueueService.getOperations(userEmail),
        false,
      );
    }
  }

  static Future<List<PendingSyncOperation>>
  _removeLocallyUndonePendingCounterIncrements(
    String userEmail,
    List<PendingSyncOperation> operations, {
    int? groupId,
  }) async {
    final undoOperationsByLocalId = <String, List<PendingSyncOperation>>{};
    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainGroupUsers ||
          operation.operationType !=
              PendingSyncOperation.undoGroupMemberCounterIncrement) {
        continue;
      }
      if (groupId != null && operation.groupId != groupId) {
        continue;
      }

      final localOperationId = _localOperationId(operation);
      if (localOperationId == null || localOperationId.isEmpty) {
        continue;
      }

      undoOperationsByLocalId
          .putIfAbsent(localOperationId, () => [])
          .add(operation);
    }

    if (undoOperationsByLocalId.isEmpty) {
      return operations;
    }

    final idsToRemove = <String>{};
    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainGroupUsers ||
          operation.operationType !=
              PendingSyncOperation.incrementGroupMemberCounter) {
        continue;
      }
      if (groupId != null && operation.groupId != groupId) {
        continue;
      }

      final matchingUndoOperations = undoOperationsByLocalId[operation.id];
      if (matchingUndoOperations == null || matchingUndoOperations.isEmpty) {
        continue;
      }

      final confirmed = await OfflineStrichService.getConfirmedIncrement(
        userEmail,
        operation.id,
        groupId: operation.groupId,
      );
      idsToRemove.add(operation.id);
      if (confirmed == null) {
        idsToRemove.addAll(matchingUndoOperations.map((entry) => entry.id));
      }
    }

    if (idsToRemove.isEmpty) {
      return operations;
    }

    await PendingSyncQueueService.removeOperations(userEmail, idsToRemove);
    return PendingSyncQueueService.getOperations(userEmail);
  }

  static Future<List<GroupMember>> _restoreMembersAfterPermanentFailure(
    String userEmail,
    int groupId,
    List<GroupMember> fallbackMembers,
  ) async {
    try {
      return await refreshGroupMembers(userEmail, groupId);
    } catch (_) {
      await saveGroupMembers(userEmail, groupId, fallbackMembers);
      return fallbackMembers;
    }
  }

  static Future<List<GroupMember>> _applyPendingOperationsOverlay(
    String userEmail,
    int groupId,
    List<GroupMember> backendMembers,
  ) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    var effectiveMembers = List<GroupMember>.from(backendMembers);

    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainGroupUsers ||
          operation.groupId != groupId) {
        continue;
      }

      if (operation.operationType == PendingSyncOperation.promoteGroupMember) {
        effectiveMembers = _replaceMemberRoleInList(
          effectiveMembers,
          _targetUserId(operation),
          GroupMemberRole.wart,
        );
        continue;
      }

      if (operation.operationType == PendingSyncOperation.demoteGroupMember) {
        effectiveMembers = _replaceMemberRoleInList(
          effectiveMembers,
          _targetUserId(operation),
          GroupMemberRole.member,
        );
        continue;
      }

      if (_changesMemberStrichCount(operation)) {
        effectiveMembers = _applySettlementDeltaToMembers(
          effectiveMembers,
          _targetUserId(operation),
          _localStrichDelta(operation),
        );
      }
    }

    return effectiveMembers;
  }

  static Future<List<GroupMember>> _currentMembers(
    String userEmail,
    int groupId,
  ) async {
    return (await getGroupMembers(userEmail, groupId)) ?? [];
  }

  static Future<bool> _hasPendingGroupUserOperations(
    String userEmail,
    int groupId,
  ) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    return _hasPendingGroupUserOperationsInList(operations, groupId);
  }

  static bool _hasPendingGroupUserOperationsInList(
    List<PendingSyncOperation> operations,
    int groupId,
  ) {
    return operations.any((operation) {
      return operation.domain == PendingSyncOperation.domainGroupUsers &&
          operation.groupId == groupId;
    });
  }

  static Future<void> _replaceMemberRole(
    String userEmail,
    int groupId,
    GroupMember updatedMember,
  ) async {
    final members = await _currentMembers(userEmail, groupId);
    final updatedMembers = _replaceMemberInList(
      members,
      updatedMember,
      addIfMissing: true,
    );
    await saveGroupMembers(userEmail, groupId, updatedMembers);
  }

  static Future<void> _mergeUpdatedMember(
    String userEmail,
    int groupId,
    GroupMember updatedMember,
  ) async {
    final members = await _currentMembers(userEmail, groupId);
    final updatedMembers = _replaceMemberInList(
      members,
      updatedMember.copyWith(
        strichCount: _normalizeStrichCount(updatedMember.strichCount),
      ),
      addIfMissing: true,
    );
    await saveGroupMembers(userEmail, groupId, updatedMembers);
  }

  static List<GroupMember> _replaceMemberInList(
    List<GroupMember> members,
    GroupMember updatedMember, {
    required bool addIfMissing,
  }) {
    var memberFound = false;
    final updatedMembers = members.map((member) {
      if (member.userId != updatedMember.userId) {
        return member;
      }

      memberFound = true;
      return updatedMember;
    }).toList();

    if (!memberFound && addIfMissing) {
      updatedMembers.add(updatedMember);
    }

    return updatedMembers;
  }

  static List<GroupMember> _replaceMemberRoleInList(
    List<GroupMember> members,
    int targetUserId,
    GroupMemberRole role,
  ) {
    return members.map((member) {
      if (member.userId != targetUserId) {
        return member;
      }

      return member.copyWith(role: role);
    }).toList();
  }

  static List<GroupMember> _removeMemberFromList(
    List<GroupMember> members,
    int targetUserId,
  ) {
    return members.where((member) => member.userId != targetUserId).toList();
  }

  static List<GroupMember> _applySettlementDeltaToMembers(
    List<GroupMember> members,
    int targetUserId,
    int localStrichDelta, {
    GroupMember? fallbackMember,
    bool addIfMissing = false,
  }) {
    var memberFound = false;
    final updatedMembers = members.map((member) {
      if (member.userId != targetUserId) {
        return member;
      }

      memberFound = true;
      return member.copyWith(
        strichCount: _normalizeStrichCount(
          member.strichCount + localStrichDelta,
        ),
      );
    }).toList();

    if (!memberFound && addIfMissing && fallbackMember != null) {
      updatedMembers.add(
        fallbackMember.copyWith(
          strichCount: _normalizeStrichCount(
            fallbackMember.strichCount + localStrichDelta,
          ),
        ),
      );
    }

    return updatedMembers;
  }

  static List<GroupMember> _setMemberStrichCount(
    List<GroupMember> members,
    int targetUserId,
    int strichCount, {
    required bool addIfMissing,
  }) {
    var memberFound = false;
    final normalizedCount = _normalizeStrichCount(strichCount);
    final updatedMembers = members.map((member) {
      if (member.userId != targetUserId) {
        return member;
      }

      memberFound = true;
      return member.copyWith(strichCount: normalizedCount);
    }).toList();

    if (!memberFound && addIfMissing) {
      return updatedMembers;
    }

    return updatedMembers;
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

  static int _localStrichDelta(PendingSyncOperation operation) {
    final rawValue = operation.payload['localStrichDelta'];
    if (rawValue is int) {
      return rawValue;
    }

    if (rawValue is num) {
      return rawValue.toInt();
    }

    return int.tryParse(rawValue.toString()) ?? 0;
  }

  static double _moneyAmount(PendingSyncOperation operation) {
    final rawValue = operation.payload['amount'];
    if (rawValue is double) {
      return rawValue;
    }

    if (rawValue is num) {
      return rawValue.toDouble();
    }

    return double.parse(rawValue.toString());
  }

  static int _intAmount(PendingSyncOperation operation) {
    final rawValue = operation.payload['amount'];
    if (rawValue is int) {
      return rawValue;
    }

    if (rawValue is num) {
      return rawValue.toInt();
    }

    return int.parse(rawValue.toString());
  }

  static String? _targetUsername(PendingSyncOperation operation) {
    final rawValue = operation.payload['targetUsername'];
    if (rawValue is! String) {
      return null;
    }

    final normalizedValue = rawValue.trim();
    if (normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  static String? _localOperationId(PendingSyncOperation operation) {
    final rawValue = operation.payload['localOperationId'];
    if (rawValue == null) {
      return null;
    }

    final normalizedValue = rawValue.toString().trim();
    if (normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  static PendingSyncOperation? _findCounterUndoOperation(
    List<PendingSyncOperation> operations,
    String localOperationId,
  ) {
    for (final operation in operations) {
      if (operation.domain != PendingSyncOperation.domainGroupUsers ||
          operation.operationType !=
              PendingSyncOperation.undoGroupMemberCounterIncrement) {
        continue;
      }

      if (_localOperationId(operation) == localOperationId) {
        return operation;
      }
    }

    return null;
  }

  static bool _affectsCurrentUser(PendingSyncOperation operation) {
    return operation.payload['affectsCurrentUser'] == true;
  }

  static int? _resolvedCountForMembers(
    List<GroupMember> members,
    int targetUserId,
    GroupSettlementResult settlement,
  ) {
    return _resolvedCountFromMembers(
      members,
      targetUserId,
      fallbackCount: settlement.resolvedStrichCount,
    );
  }

  static int? _resolvedCountFromMembers(
    List<GroupMember> members,
    int targetUserId, {
    int? fallbackCount,
  }) {
    for (final member in members) {
      if (member.userId == targetUserId) {
        return member.strichCount;
      }
    }

    return fallbackCount;
  }

  static bool _isCounterIncrementOperation(PendingSyncOperation operation) {
    return operation.operationType ==
        PendingSyncOperation.incrementGroupMemberCounter;
  }

  static bool _isCounterUndoOperation(PendingSyncOperation operation) {
    return operation.operationType ==
        PendingSyncOperation.undoGroupMemberCounterIncrement;
  }

  static bool _changesMemberStrichCount(PendingSyncOperation operation) {
    return _isCounterIncrementOperation(operation) ||
        _isCounterUndoOperation(operation) ||
        _isSettlementOperation(operation);
  }

  static bool _isSettlementOperation(PendingSyncOperation operation) {
    return operation.operationType ==
            PendingSyncOperation.settleGroupMemberMoney ||
        operation.operationType ==
            PendingSyncOperation.settleGroupMemberStriche;
  }

  static bool _isPermanentFailure(int? statusCode) {
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }

  static DateTime _undoExpiresAt(
    PendingSyncOperation operation,
    ConfirmedCounterIncrement confirmed,
  ) {
    final rawValue = operation.payload['undoExpiresAt'];
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return DateTime.parse(rawValue).toUtc();
    }

    return confirmed.undoExpiresAt.toUtc();
  }

  static bool _isUndoExpired(DateTime undoExpiresAt) {
    return !DateTime.now().toUtc().isBefore(undoExpiresAt);
  }

  static String _friendlyRoleActionError(
    GroupApiException exception,
    PendingSyncOperation operation,
    String fallbackMessage,
  ) {
    final message = exception.message.trim();

    if (operation.operationType == PendingSyncOperation.demoteGroupMember &&
        _isLastWartDemotionBlocked(exception.statusCode, message)) {
      return 'Der letzte Bierlistenwart kann nicht herabgestuft werden';
    }

    if (_isGroupUnavailableActionError(exception.statusCode, message)) {
      return 'Gruppe nicht verfügbar oder kein Zugriff';
    }

    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        if (_isMemberUnavailableError(message)) {
          return 'Mitglied wurde nicht gefunden';
        }
        return 'Gruppe nicht verfügbar oder kein Zugriff';
      default:
        if (message.isNotEmpty) {
          return message;
        }
        return fallbackMessage;
    }
  }

  static String _friendlyRemoveMemberError(GroupApiException exception) {
    final message = exception.message.trim();
    if (_isNetworkError(exception)) {
      return 'Keine Verbindung';
    }

    if (_isLastWartRemovalBlocked(exception.statusCode, message)) {
      return 'Der letzte Bierlistenwart kann nicht entfernt werden';
    }

    if (_isGroupUnavailableActionError(exception.statusCode, message)) {
      return 'Gruppe nicht verfügbar oder kein Zugriff';
    }

    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        if (_isMemberUnavailableError(message)) {
          return 'Mitglied wurde nicht gefunden';
        }
        return 'Gruppe nicht verfügbar oder kein Zugriff';
      case 409:
        return message.isNotEmpty
            ? message
            : 'Mitglied kann gerade nicht entfernt werden';
      default:
        return message.isNotEmpty
            ? message
            : 'Mitglied konnte nicht entfernt werden';
    }
  }

  static String _friendlySettlementError(
    GroupSettlementApiException exception, {
    required String operationType,
    required String fallbackMessage,
  }) {
    switch (exception.statusCode) {
      case 400:
        return operationType == PendingSyncOperation.settleGroupMemberMoney
            ? 'Ungültiger Betrag'
            : 'Ungültige Anzahl';
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Mitglied oder Gruppe nicht gefunden';
      default:
        final message = exception.message.trim();
        return message.isNotEmpty ? message : fallbackMessage;
    }
  }

  static String _friendlyCounterIncrementError(
    GroupCounterApiException exception, {
    required String fallbackMessage,
  }) {
    switch (exception.statusCode) {
      case 400:
        return 'Ungültige Anzahl';
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Mitglied oder Gruppe nicht gefunden';
      default:
        final message = exception.message.trim();
        return message.isNotEmpty ? message : fallbackMessage;
    }
  }

  static String _friendlyCounterUndoError(GroupCounterApiException exception) {
    final normalizedMessage = exception.message.trim().toLowerCase();
    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Strich-Request nicht gefunden';
      case 409:
        if (normalizedMessage.contains('zeitfenster') ||
            normalizedMessage.contains('abgelaufen')) {
          return 'Undo-Zeitfenster abgelaufen';
        }
        if (normalizedMessage.contains('rückgängig') ||
            normalizedMessage.contains('rueckgaengig')) {
          return 'Strich-Request kann nicht mehr rückgängig gemacht werden';
        }
        return exception.message.trim().isNotEmpty
            ? exception.message.trim()
            : 'Strich konnte nicht rückgängig gemacht werden';
      default:
        return exception.message.trim().isNotEmpty
            ? exception.message.trim()
            : 'Strich konnte nicht rückgängig gemacht werden';
    }
  }

  static bool _isLastWartDemotionBlocked(int? statusCode, String message) {
    final normalizedMessage = message.toLowerCase();

    if (statusCode == 409) {
      return true;
    }

    return normalizedMessage.contains('letzte') ||
        normalizedMessage.contains('last admin') ||
        normalizedMessage.contains('last wart') ||
        normalizedMessage.contains('only admin') ||
        normalizedMessage.contains('mindestens ein');
  }

  static bool _isLastWartRemovalBlocked(int? statusCode, String message) {
    final normalizedMessage = message.toLowerCase();
    return _isLastWartDemotionBlocked(statusCode, message) ||
        normalizedMessage.contains('entfernt') ||
        normalizedMessage.contains('removed');
  }

  static bool _isGroupUnavailableActionError(int? statusCode, String message) {
    if (statusCode != 403 && statusCode != 404) {
      return false;
    }

    final normalizedMessage = message.toLowerCase();
    return normalizedMessage.contains('gruppe') ||
        normalizedMessage.contains('group') ||
        normalizedMessage.contains('zugriff') ||
        normalizedMessage.contains('access') ||
        normalizedMessage.contains('forbidden');
  }

  static bool _isMemberUnavailableError(String message) {
    final normalizedMessage = message.toLowerCase();
    return normalizedMessage.contains('mitglied') ||
        normalizedMessage.contains('member') ||
        normalizedMessage.contains('user');
  }

  static bool _shouldReloadUi(int? statusCode) {
    return statusCode == 403 || statusCode == 404;
  }

  static bool _isNetworkError(GroupApiException exception) {
    final message = exception.message.trim().toLowerCase();
    return exception.statusCode == null &&
        (message == 'netzwerkfehler' || message.contains('timeout'));
  }

  static int _normalizeStrichCount(int value) {
    return value < 0 ? 0 : value;
  }

  static String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _groupMembersKey(String userEmail, int groupId) {
    return 'group_members_cache_${userEmail}_$groupId';
  }
}

class _GroupUsersUndoSyncResult {
  final List<PendingSyncOperation> operations;
  final bool successful;

  const _GroupUsersUndoSyncResult(this.operations, this.successful);
}

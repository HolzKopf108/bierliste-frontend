import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/group_member.dart';
import '../models/group_settings.dart';
import '../providers/auth_provider.dart';
import '../providers/group_role_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/user_provider.dart';
import '../services/connectivity_service.dart';
import '../services/group_api_service.dart';
import '../services/http_service.dart';
import '../services/offline_group_settings_service.dart';
import '../services/offline_group_users_service.dart';
import '../utils/money_input_formatter.dart';
import '../widgets/toast.dart';

enum SortOption { alphabet, strichCount }

enum _MemberAction {
  bookStriche,
  settleMoney,
  settleStriche,
  promoteToWart,
  demoteToMember,
}

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
  GroupSettings? _groupSettings;
  double _pricePerStrich = 0;
  bool _isLoading = true;
  int? _updatingMemberUserId;
  String? _loadErrorMessage;
  SyncProvider? _syncProvider;
  bool _wasOnline = false;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    unawaited(_loadDisplaySettings());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final syncProvider = context.read<SyncProvider>();
    if (_syncProvider == syncProvider) {
      return;
    }

    _syncProvider?.removeListener(_handleSyncProviderChanged);
    _syncProvider = syncProvider;
    _wasOnline = syncProvider.isAppOnline;
    _wasSyncing = syncProvider.isSyncing;
    syncProvider.addListener(_handleSyncProviderChanged);
  }

  @override
  void dispose() {
    _syncProvider?.removeListener(_handleSyncProviderChanged);
    super.dispose();
  }

  Future<void> _loadMembers({bool showLoading = true}) async {
    final userEmail = context.read<AuthProvider>().userEmail;
    final groupRoleProvider = context.read<GroupRoleProvider>();

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
      });
    } else {
      _loadErrorMessage = null;
    }

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
        _members = [];
        _isLoading = false;
        _loadErrorMessage = 'Keine Berechtigung';
      });
    } on GroupApiException catch (e) {
      if (_isGroupUnavailableError(e.statusCode)) {
        if (!mounted) return;
        setState(() {
          _members = [];
          _isLoading = false;
          _loadErrorMessage = 'Gruppe nicht verfügbar oder kein Zugriff';
        });
        return;
      }

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

  void _handleSyncProviderChanged() {
    final syncProvider = _syncProvider;
    if (syncProvider == null) {
      return;
    }

    final isOnline = syncProvider.isAppOnline;
    final isSyncing = syncProvider.isSyncing;
    final shouldReload =
        (!_wasOnline && isOnline) || (_wasSyncing && !isSyncing);

    _wasOnline = isOnline;
    _wasSyncing = isSyncing;

    if (shouldReload &&
        mounted &&
        !_isLoading &&
        _updatingMemberUserId == null) {
      unawaited(_loadMembers(showLoading: false));
      unawaited(_loadDisplaySettings());
    }
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

  Future<void> _handlePopupAction(
    GroupMember member,
    _MemberAction action,
  ) async {
    switch (action) {
      case _MemberAction.bookStriche:
        await _handleBookStricheAction(member);
        return;
      case _MemberAction.promoteToWart:
      case _MemberAction.demoteToMember:
        await _handleRoleAction(member, action);
        return;
      case _MemberAction.settleMoney:
        await _handleMoneySettlementAction(member);
        return;
      case _MemberAction.settleStriche:
        await _handleStricheSettlementAction(member);
        return;
    }
  }

  Future<void> _handleBookStricheAction(GroupMember member) async {
    if (_updatingMemberUserId != null) {
      return;
    }

    final amount = await _showCounterIncrementDialog(member);
    if (!mounted || amount == null) {
      return;
    }

    final successMessage = amount == 1
        ? 'Strich für ${member.username} gebucht'
        : '$amount Striche für ${member.username} gebucht';
    final pendingMessage = amount == 1
        ? 'Strich für ${member.username} gebucht und wird synchronisiert'
        : '$amount Striche für ${member.username} gebucht und werden synchronisiert';

    await _handleMemberActionExecution(
      member,
      execute: (userEmail) => OfflineGroupUsersService.incrementMemberCounter(
        userEmail,
        widget.groupId,
        member,
        amount,
        affectsCurrentUser: _isOwnMember(member),
      ),
      successMessage: successMessage,
      pendingMessage: pendingMessage,
      fallbackErrorMessage: 'Striche konnten nicht gespeichert werden',
      toastActionLabel: 'Rückgängig',
      onToastActionTap: () {},
    );
  }

  Future<void> _handleRoleAction(
    GroupMember member,
    _MemberAction action,
  ) async {
    if (_updatingMemberUserId != null) {
      return;
    }

    final userEmail = context.read<AuthProvider>().userEmail;
    final groupRoleProvider = context.read<GroupRoleProvider>();
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
        _ => throw UnsupportedError('Ungültige Rollenaktion'),
      };
      if (!mounted) return;

      setState(() {
        _members = result.members;
        _loadErrorMessage = null;
      });

      if (result.errorMessage != null) {
        Toast.show(context, result.errorMessage!, type: ToastType.warning);
        if (result.shouldReloadUi) {
          unawaited(_reloadAfterActionFailure(userEmail, groupRoleProvider));
        }
      } else {
        Toast.show(
          context,
          result.hasPendingSync
              ? 'Rollenänderung gespeichert und wird synchronisiert'
              : 'Rollenänderung gespeichert',
          type: result.hasPendingSync ? ToastType.info : ToastType.success,
        );
      }

      if (result.hasPendingSync) {
        unawaited(syncProvider.markPendingSync());
      }
    } on UnauthorizedException {
      if (!mounted) return;
      Toast.show(context, 'Keine Berechtigung', type: ToastType.warning);
      unawaited(_reloadAfterActionFailure(userEmail, groupRoleProvider));
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

  Future<void> _handleMoneySettlementAction(GroupMember member) async {
    if (_updatingMemberUserId != null) {
      return;
    }

    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      Toast.show(context, 'Berechtigung konnte nicht geprüft werden');
      return;
    }

    final groupSettings = await _resolveSettlementSettings(userEmail);
    if (!mounted) {
      return;
    }
    if (groupSettings == null || groupSettings.pricePerStrich <= 0) {
      Toast.show(
        context,
        'Preis pro Strich konnte nicht geladen werden',
        type: ToastType.warning,
      );
      return;
    }

    final amount = await _showMoneySettlementDialog(member, groupSettings);
    if (!mounted || amount == null) {
      return;
    }

    final resultingReduction =
        OfflineGroupUsersService.calculateMoneySettlementStriche(
          amount,
          groupSettings.pricePerStrich,
          allowArbitraryMoneySettlements:
              groupSettings.allowArbitraryMoneySettlements,
        ) ??
        0;
    final ignoredAmount = groupSettings.allowArbitraryMoneySettlements
        ? (amount - (resultingReduction * groupSettings.pricePerStrich))
              .clamp(0.0, amount)
              .toDouble()
        : 0.0;
    final ignoredAmountText = ignoredAmount > 0.0001
        ? '\nRestbetrag ${_formatMoney(ignoredAmount)} € wird ignoriert.'
        : '';
    final successMessage = resultingReduction > 0
        ? 'Geldabzug gespeichert'
        : 'Kein voller Strich, daher keine Änderung';
    final pendingMessage = resultingReduction > 0
        ? 'Geldabzug gespeichert und wird synchronisiert'
        : 'Kein voller Strich, daher keine Änderung; Anfrage wird synchronisiert';

    final confirmed = await _showConfirmationDialog(
      title: 'Geld abziehen',
      message:
          'Wirklich ${_formatMoney(amount)} € bei ${member.username} abziehen?\n'
          'Dabei werden $resultingReduction ${_strichLabel(resultingReduction)} reduziert.'
          '$ignoredAmountText',
    );
    if (!mounted || !confirmed) {
      return;
    }

    await _handleMemberActionExecution(
      member,
      execute: (userEmail) => OfflineGroupUsersService.settleMemberMoney(
        userEmail,
        widget.groupId,
        member,
        amount,
        pricePerStrich: groupSettings.pricePerStrich,
        allowArbitraryMoneySettlements:
            groupSettings.allowArbitraryMoneySettlements,
        affectsCurrentUser: _isOwnMember(member),
      ),
      successMessage: successMessage,
      pendingMessage: pendingMessage,
      fallbackErrorMessage: 'Geld konnte nicht abgezogen werden',
    );
  }

  Future<void> _handleStricheSettlementAction(GroupMember member) async {
    if (_updatingMemberUserId != null) {
      return;
    }

    final amount = await _showStricheSettlementDialog(member);
    if (!mounted || amount == null) {
      return;
    }

    final confirmed = await _showConfirmationDialog(
      title: 'Striche abziehen',
      message:
          'Wirklich $amount ${_strichLabel(amount)} bei ${member.username} abziehen?',
    );
    if (!mounted || !confirmed) {
      return;
    }

    await _handleMemberActionExecution(
      member,
      execute: (userEmail) => OfflineGroupUsersService.settleMemberStriche(
        userEmail,
        widget.groupId,
        member,
        amount,
        affectsCurrentUser: _isOwnMember(member),
      ),
      successMessage: 'Strichstand gespeichert',
      pendingMessage: 'Strichstand gespeichert und wird synchronisiert',
      fallbackErrorMessage: 'Striche konnten nicht abgezogen werden',
    );
  }

  Future<void> _handleMemberActionExecution(
    GroupMember member, {
    required Future<OfflineGroupUsersActionResult> Function(String userEmail)
    execute,
    required String successMessage,
    required String pendingMessage,
    required String fallbackErrorMessage,
    String? toastActionLabel,
    VoidCallback? onToastActionTap,
  }) async {
    final userEmail = context.read<AuthProvider>().userEmail;
    final groupRoleProvider = context.read<GroupRoleProvider>();
    final syncProvider = context.read<SyncProvider>();

    if (userEmail == null) {
      Toast.show(context, 'Berechtigung konnte nicht geprüft werden');
      return;
    }

    setState(() {
      _updatingMemberUserId = member.userId;
    });

    try {
      final result = await execute(userEmail);
      if (!mounted) {
        return;
      }

      setState(() {
        _members = result.members;
        _loadErrorMessage = null;
      });

      if (result.errorMessage != null) {
        Toast.show(context, result.errorMessage!, type: ToastType.warning);
        if (result.shouldReloadUi) {
          unawaited(_reloadAfterActionFailure(userEmail, groupRoleProvider));
        }
      } else {
        Toast.show(
          context,
          result.hasPendingSync ? pendingMessage : successMessage,
          type: result.hasPendingSync ? ToastType.info : ToastType.success,
          actionLabel: toastActionLabel,
          onActionTap: onToastActionTap,
        );
      }

      if (result.hasPendingSync) {
        unawaited(syncProvider.markPendingSync());
      }
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }
      Toast.show(context, 'Keine Berechtigung', type: ToastType.warning);
      unawaited(_reloadAfterActionFailure(userEmail, groupRoleProvider));
    } catch (_) {
      if (!mounted) {
        return;
      }
      Toast.show(context, fallbackErrorMessage, type: ToastType.warning);
    } finally {
      if (mounted) {
        setState(() {
          _updatingMemberUserId = null;
        });
      }
    }
  }

  Future<GroupSettings?> _resolveSettlementSettings(String userEmail) async {
    final cachedSettings = await OfflineGroupSettingsService.getGroupSettings(
      userEmail,
      widget.groupId,
    );
    if (cachedSettings != null && mounted) {
      setState(() {
        _applyDisplaySettings(cachedSettings);
      });
    }
    if (!await ConnectivityService.isOnline()) {
      return cachedSettings;
    }

    try {
      final freshSettings =
          await OfflineGroupSettingsService.refreshGroupSettings(
            userEmail,
            widget.groupId,
          );
      if (mounted) {
        setState(() {
          _applyDisplaySettings(freshSettings);
        });
      }
      return freshSettings;
    } on UnauthorizedException {
      rethrow;
    } catch (_) {
      return cachedSettings;
    }
  }

  Future<void> _loadDisplaySettings() async {
    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      return;
    }

    final cachedSettings = await OfflineGroupSettingsService.getGroupSettings(
      userEmail,
      widget.groupId,
    );
    if (cachedSettings != null && mounted) {
      setState(() {
        _applyDisplaySettings(cachedSettings);
      });
    }

    if (!await ConnectivityService.isOnline()) {
      return;
    }

    try {
      final freshSettings =
          await OfflineGroupSettingsService.refreshGroupSettings(
            userEmail,
            widget.groupId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyDisplaySettings(freshSettings);
      });
    } on UnauthorizedException {
      return;
    } catch (_) {
      return;
    }
  }

  void _applyDisplaySettings(GroupSettings settings) {
    _groupSettings = settings;
    _pricePerStrich = settings.pricePerStrich;
  }

  Future<double?> _showMoneySettlementDialog(
    GroupMember member,
    GroupSettings groupSettings,
  ) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        String? errorText;

        void submit(StateSetter setDialogState) {
          final parsed = _parseMoneyAmount(controller.text);
          if (parsed == null || parsed <= 0) {
            setDialogState(() {
              errorText = 'Bitte einen gültigen Betrag eingeben';
            });
            return;
          }

          final settlementStriche =
              OfflineGroupUsersService.calculateMoneySettlementStriche(
                parsed,
                groupSettings.pricePerStrich,
                allowArbitraryMoneySettlements:
                    groupSettings.allowArbitraryMoneySettlements,
              );
          if (!groupSettings.allowArbitraryMoneySettlements &&
              settlementStriche == null) {
            setDialogState(() {
              errorText =
                  'Betrag muss ein Vielfaches von ${_formatMoney(groupSettings.pricePerStrich)} € sein';
            });
            return;
          }

          Navigator.of(dialogContext).pop(parsed);
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Geld bei ${member.username} abziehen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preis pro Strich: ${_formatMoney(groupSettings.pricePerStrich)} €',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    groupSettings.allowArbitraryMoneySettlements
                        ? 'Beliebige Beträge sind erlaubt. Es wird immer auf volle Striche abgerundet; der Restbetrag wird ignoriert.'
                        : 'Es sind nur Vielfache des Preises pro Strich erlaubt.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [MoneyInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Betrag',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onSubmitted: (_) => submit(setDialogState),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => submit(setDialogState),
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
    return amount;
  }

  Future<int?> _showCounterIncrementDialog(GroupMember member) {
    return _showStrichAmountDialog(
      title: 'Striche für ${member.username} buchen',
    );
  }

  Future<int?> _showStricheSettlementDialog(GroupMember member) {
    return _showStrichAmountDialog(
      title: 'Striche bei ${member.username} abziehen',
    );
  }

  Future<int?> _showStrichAmountDialog({required String title}) async {
    final controller = TextEditingController();
    controller.text = '1';
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        String? errorText;

        void submit(StateSetter setDialogState) {
          final parsed = int.tryParse(controller.text.trim());
          if (parsed == null || parsed <= 0) {
            setDialogState(() {
              errorText = 'Bitte eine gültige Anzahl eingeben';
            });
            return;
          }

          Navigator.of(dialogContext).pop(parsed);
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Anzahl',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onSubmitted: (_) => submit(setDialogState),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => submit(setDialogState),
                  child: const Text('Weiter'),
                ),
              ],
            );
          },
        );
      },
    );
    return amount;
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String message,
  }) async {
    return (await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Bestätigen'),
                ),
              ],
            );
          },
        )) ??
        false;
  }

  Future<void> _reloadAfterActionFailure(
    String userEmail,
    GroupRoleProvider groupRoleProvider,
  ) async {
    try {
      await groupRoleProvider.refreshRole(userEmail, widget.groupId);
    } catch (_) {}

    if (!mounted) return;

    await _loadMembers(showLoading: false);
    await _loadDisplaySettings();
  }

  bool _isOwnMember(GroupMember member) {
    final currentUsername = context.read<UserProvider>().user?.username.trim();
    if (currentUsername == null || currentUsername.isEmpty) {
      return false;
    }

    return currentUsername.toLowerCase() ==
        member.username.trim().toLowerCase();
  }

  double? _parseMoneyAmount(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.replaceAll('.', ',');
    if (!RegExp(r'^\d{1,8}(,\d{0,2})?$').hasMatch(normalized)) {
      return null;
    }

    final value = double.tryParse(normalized.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      return null;
    }

    return value;
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String? _memberAmountText(GroupMember member) {
    if (_pricePerStrich <= 0) {
      return null;
    }

    return '${_formatMoney(member.strichCount * _pricePerStrich)} €';
  }

  bool _canBookForOtherMembers(GroupMemberRole? ownRole) {
    if (ownRole == GroupMemberRole.wart) {
      return true;
    }

    if (ownRole != GroupMemberRole.member) {
      return false;
    }

    final groupSettings = _groupSettings;
    if (groupSettings == null) {
      return false;
    }

    return !groupSettings.onlyWartsCanBookForOthers;
  }

  List<PopupMenuEntry<_MemberAction>> _buildMemberMenuEntries(
    GroupMember member,
    GroupMemberRole? ownRole,
  ) {
    final theme = Theme.of(context);
    final entries = <PopupMenuEntry<_MemberAction>>[];
    final canBookForOthers = _canBookForOtherMembers(ownRole);
    final canManageMembers = ownRole == GroupMemberRole.wart;

    if (canBookForOthers) {
      entries.add(
        _buildMenuItem(
          action: _MemberAction.bookStriche,
          icon: Icons.add_circle_outline_rounded,
          label: 'Striche buchen',
          theme: theme,
          emphasized: true,
        ),
      );
    }

    if (canManageMembers) {
      if (entries.isNotEmpty) {
        entries.add(const PopupMenuDivider(height: 10));
      }

      entries.add(
        _buildMenuItem(
          action: _MemberAction.settleMoney,
          icon: Icons.payments_outlined,
          label: 'Geld abziehen',
          theme: theme,
        ),
      );
      entries.add(
        _buildMenuItem(
          action: _MemberAction.settleStriche,
          icon: Icons.remove_circle_outline_rounded,
          label: 'Striche abziehen',
          theme: theme,
        ),
      );
      entries.add(const PopupMenuDivider(height: 10));
      entries.add(
        _buildMenuItem(
          action: member.role == GroupMemberRole.wart
              ? _MemberAction.demoteToMember
              : _MemberAction.promoteToWart,
          icon: member.role == GroupMemberRole.wart
              ? Icons.person_remove_alt_1_outlined
              : Icons.verified_user_outlined,
          label: member.role == GroupMemberRole.wart
              ? 'Bierlistenwart entfernen'
              : 'Zum Bierlistenwart machen',
          theme: theme,
        ),
      );
    }

    return entries;
  }

  PopupMenuItem<_MemberAction> _buildMenuItem({
    required _MemberAction action,
    required IconData icon,
    required String label,
    required ThemeData theme,
    bool emphasized = false,
  }) {
    final colorScheme = theme.colorScheme;
    final foregroundColor = emphasized
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final iconColor = emphasized
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return PopupMenuItem<_MemberAction>(
      value: action,
      child: Container(
        padding: emphasized
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : EdgeInsets.zero,
        decoration: emphasized
            ? BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isGroupUnavailableError(int? statusCode) {
    return statusCode == 403 || statusCode == 404;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final ownRole = context.watch<GroupRoleProvider>().roleForGroup(
      widget.groupId,
    );
    final sortedMembers = _sortedMembers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitglieder'),
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
                      onPressed: () => _loadMembers(),
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
                    onPressed: () => _loadMembers(),
                    child: const Text('Erneut laden'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadMembers(showLoading: false),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                itemCount: sortedMembers.length,
                itemBuilder: (context, index) {
                  final member = sortedMembers[index];
                  final menuEntries = _buildMemberMenuEntries(member, ownRole);
                  final strichLabel = _strichLabel(member.strichCount);
                  final memberAmountText = _memberAmountText(member);
                  final showWartBadge = member.role == GroupMemberRole.wart;
                  final showMemberMenu = menuEntries.isNotEmpty;
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
                                      horizontal: 7,
                                      vertical: 3,
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
                                          size: 13,
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
                            width: 96,
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
                                const SizedBox(height: 1),
                                Text(
                                  strichLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.hintColor,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                if (memberAmountText != null) ...[
                                  Text(
                                    memberAmountText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
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
                                    tooltip: 'Aktionen',
                                    icon: const Icon(Icons.more_horiz_rounded),
                                    position: PopupMenuPosition.under,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    onSelected: (action) =>
                                        _handlePopupAction(member, action),
                                    itemBuilder: (context) => menuEntries,
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

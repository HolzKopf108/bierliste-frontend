import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/group_member_notification.dart';
import '../providers/sync_provider.dart';
import '../providers/group_role_provider.dart';
import '../routes/app_routes.dart';
import '../services/android_notification_service.dart';
import '../services/connectivity_service.dart';
import '../services/group_counter_api_service.dart';
import '../services/group_notification_api_service.dart';
import '../services/http_service.dart';
import '../services/offline_group_settings_service.dart';
import '../services/offline_group_users_service.dart';
import '../services/offline_strich_service.dart';
import '../widgets/toast.dart';
import '../providers/auth_provider.dart';
import '../utils/navigation_helper.dart';

enum _StrichSubmitResult { failed, savedPending }

class GroupHomePage extends StatefulWidget {
  final int groupId;
  final String? groupName;

  const GroupHomePage({super.key, required this.groupId, this.groupName});

  @override
  State<GroupHomePage> createState() => _GroupHomePageState();
}

class _GroupHomePageState extends State<GroupHomePage>
    with WidgetsBindingObserver {
  final GroupCounterApiService _groupCounterApiService =
      GroupCounterApiService();
  final GroupNotificationApiService _groupNotificationApiService =
      GroupNotificationApiService();
  static const _minimumSubmitDuration = Duration(milliseconds: 250);
  static const _primaryActionTransitionDuration = Duration(milliseconds: 220);
  int _strichCount = 0;
  double _pricePerStrich = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  int? _confirmingNotificationId;
  String? _loadErrorMessage;
  String? _groupName;
  List<GroupMemberNotification> _pendingNotifications = const [];
  SyncProvider? _syncProvider;
  StreamSubscription<int>? _incomingGroupNotificationSubscription;
  bool _wasOnline = false;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _groupName = widget.groupName?.trim();
    _listenToIncomingGroupNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_loadCounter());
      unawaited(_loadGroupRole());
      unawaited(_loadGroupSettings());
      unawaited(_loadPendingNotifications());
    });
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
    WidgetsBinding.instance.removeObserver(this);
    _syncProvider?.removeListener(_handleSyncProviderChanged);
    _incomingGroupNotificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) {
      return;
    }

    unawaited(_loadPendingNotifications());
  }

  Future<void> _loadGroupRole({bool forceRefresh = false}) async {
    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      return;
    }

    await context.read<GroupRoleProvider>().loadRole(
      userEmail,
      widget.groupId,
      forceRefresh: forceRefresh,
    );
  }

  void _listenToIncomingGroupNotifications() {
    _incomingGroupNotificationSubscription ??= AndroidNotificationService
        .instance
        .incomingGroupNotifications
        .listen((groupId) {
          if (!mounted || groupId != widget.groupId) {
            return;
          }

          unawaited(_loadPendingNotifications());
        });
  }

  void _handleSyncProviderChanged() {
    final syncProvider = _syncProvider;
    if (syncProvider == null) return;

    final isOnline = syncProvider.isAppOnline;
    final isSyncing = syncProvider.isSyncing;
    final shouldReload =
        (!_wasOnline && isOnline) || (_wasSyncing && !isSyncing);

    _wasOnline = isOnline;
    _wasSyncing = isSyncing;

    if (shouldReload && mounted && !_isLoading && !_isSubmitting) {
      _loadCounter(showLoading: false, triggerSync: false);
      unawaited(_loadGroupSettings());
      unawaited(_loadPendingNotifications());
    }
  }

  Future<void> _loadCounter({
    bool showLoading = true,
    bool triggerSync = true,
  }) async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

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
        _isLoading = false;
        _loadErrorMessage = 'Counter konnte nicht geladen werden';
      });
      return;
    }

    try {
      if (triggerSync && syncProvider.isAppOnline) {
        unawaited(syncProvider.requestSync());
      }

      final counter = await _groupCounterApiService.fetchMyGroupCounter(
        widget.groupId,
      );
      final pendingCount = await OfflineStrichService.getPendingSum(
        userEmail,
        widget.groupId,
      );
      await OfflineStrichService.saveLastOnlineCounter(
        userEmail,
        widget.groupId,
        counter.count,
      );
      if (!mounted) return;

      setState(() {
        _strichCount = counter.count + pendingCount;
        _isLoading = false;
        _loadErrorMessage = null;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } on GroupCounterApiException catch (e) {
      await _loadOfflineCounter(userEmail, fallbackErrorMessage: e.message);
    } catch (_) {
      await _loadOfflineCounter(
        userEmail,
        fallbackErrorMessage: 'Gruppen-Counter konnte nicht geladen werden',
      );
    }
  }

  Future<_StrichSubmitResult> _incrementStrich([int amount = 1]) async {
    if (_isSubmitting) {
      return _StrichSubmitResult.failed;
    }

    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

    if (userEmail == null) {
      return _StrichSubmitResult.failed;
    }

    setState(() {
      _isSubmitting = true;
    });
    final startedAt = DateTime.now();

    try {
      return await _storePendingIncrement(userEmail, amount, syncProvider);
    } on UnauthorizedException {
      return _StrichSubmitResult.failed;
    } catch (_) {
      if (!mounted) return _StrichSubmitResult.failed;
      Toast.show(context, 'Strich konnte nicht gespeichert werden');
    } finally {
      await _ensureMinimumSubmitDuration(startedAt);
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }

    return _StrichSubmitResult.failed;
  }

  Future<void> _loadOfflineCounter(
    String userEmail, {
    required String fallbackErrorMessage,
  }) async {
    final lastOnlineCount = await OfflineStrichService.getLastOnlineCounter(
      userEmail,
      widget.groupId,
    );
    final pendingCount = await OfflineStrichService.getPendingSum(
      userEmail,
      widget.groupId,
    );
    if (!mounted) return;

    setState(() {
      _strichCount = lastOnlineCount + pendingCount;
      _isLoading = false;
      _loadErrorMessage = null;
    });

    if (lastOnlineCount == 0 && pendingCount == 0) {
      setState(() {
        _loadErrorMessage = fallbackErrorMessage;
      });
    }
  }

  Future<_StrichSubmitResult> _storePendingIncrement(
    String userEmail,
    int amount,
    SyncProvider syncProvider,
  ) async {
    final operation = await OfflineStrichService.addPendingOwnCounterIncrement(
      userEmail,
      widget.groupId,
      amount,
    );
    if (!mounted) return _StrichSubmitResult.failed;

    setState(() {
      _strichCount += amount;
      _loadErrorMessage = null;
    });
    _showSavedToast(amount, operation.id);
    unawaited(syncProvider.markPendingSync());
    return _StrichSubmitResult.savedPending;
  }

  Future<void> _ensureMinimumSubmitDuration(DateTime startedAt) async {
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _minimumSubmitDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _handleUndoSavedIncrement(
    String localOperationId,
    int amount,
  ) async {
    final userEmail = context.read<AuthProvider>().userEmail;
    final syncProvider = context.read<SyncProvider>();
    if (userEmail == null) {
      Toast.show(
        context,
        'Berechtigung konnte nicht geprüft werden',
        type: ToastType.warning,
      );
      return;
    }

    final result = await OfflineStrichService.undoOwnCounterIncrement(
      userEmail,
      widget.groupId,
      localOperationId,
      amount,
      isSyncing: syncProvider.isSyncing,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _strichCount = result.count;
      _loadErrorMessage = null;
    });

    if (result.errorMessage != null) {
      Toast.show(context, result.errorMessage!, type: ToastType.warning);
    } else {
      final message = amount == 1
          ? result.hasPendingSync
                ? 'Rückgängig gespeichert und wird synchronisiert'
                : 'Strich rückgängig gemacht'
          : result.hasPendingSync
          ? '$amount Striche werden rückgängig gemacht und synchronisiert'
          : '$amount Striche rückgängig gemacht';
      Toast.show(
        context,
        message,
        type: result.hasPendingSync ? ToastType.info : ToastType.success,
      );
    }

    if (result.hasPendingSync) {
      unawaited(syncProvider.markPendingSync());
    } else {
      unawaited(syncProvider.refreshPendingSyncStatus());
    }
  }

  void _showSavedToast(int amount, String localOperationId) {
    final message = switch (amount) {
      1 => 'Strich gespeichert',
      _ => '$amount Striche gespeichert',
    };

    Toast.show(
      context,
      message,
      type: ToastType.success,
      actionLabel: 'Rückgängig',
      onActionTap: () => _handleUndoSavedIncrement(localOperationId, amount),
    );
  }

  String _strichLabel(int amount) {
    return amount == 1 ? 'Strich' : 'Striche';
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _saldoStatusLabel(int strichCount) {
    if (strichCount > 0) {
      return 'Schulden';
    }
    if (strichCount < 0) {
      return 'Guthaben';
    }
    return 'Ausgeglichen';
  }

  Color _saldoColor(ThemeData theme, int strichCount) {
    if (strichCount > 0) {
      return theme.colorScheme.error;
    }
    if (strichCount < 0) {
      return const Color(0xFF2E7D32);
    }
    return theme.colorScheme.onSurface;
  }

  String? _groupNameForArgs() {
    final groupName = _groupName?.trim();
    if (groupName == null || groupName.isEmpty) {
      return null;
    }
    return groupName;
  }

  Future<void> _loadGroupSettings() async {
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
        _groupName = cachedSettings.name;
        _pricePerStrich = cachedSettings.pricePerStrich;
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
      if (!mounted) return;
      setState(() {
        _groupName = freshSettings.name;
        _pricePerStrich = freshSettings.pricePerStrich;
      });
    } on UnauthorizedException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> _loadPendingNotifications() async {
    try {
      final notifications = await _groupNotificationApiService
          .fetchMyNotifications(widget.groupId);
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingNotifications = _openNotifications(notifications);
      });

      await _maybeConfirmPendingNotificationAction();
    } on UnauthorizedException {
      return;
    } catch (_) {
      return;
    }
  }

  List<GroupMemberNotification> _openNotifications(
    List<GroupMemberNotification> notifications,
  ) {
    return notifications.where((notification) => notification.isOpen).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _maybeConfirmPendingNotificationAction() async {
    if (_confirmingNotificationId != null) {
      return;
    }

    final notificationId = await AndroidNotificationService.instance
        .pendingConfirmationNotificationIdForGroup(widget.groupId);
    if (notificationId == null) {
      return;
    }

    await _confirmNotification(notificationId);
  }

  Future<void> _confirmNotification(int notificationId) async {
    if (_confirmingNotificationId != null) {
      return;
    }

    setState(() {
      _confirmingNotificationId = notificationId;
    });

    try {
      await _groupNotificationApiService.confirmNotification(
        widget.groupId,
        notificationId,
      );
      await AndroidNotificationService.instance.clearPendingConfirmation(
        widget.groupId,
        notificationId,
      );
      await _refreshMemberNotificationStatus();
      await _loadPendingNotifications();
      if (!mounted) {
        return;
      }

      Toast.show(
        context,
        'Benachrichtigung bestätigt',
        type: ToastType.success,
      );
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }
      Toast.show(context, 'Keine Berechtigung', type: ToastType.warning);
    } on GroupNotificationApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 409) {
        await AndroidNotificationService.instance.clearPendingConfirmation(
          widget.groupId,
          notificationId,
        );
      }
      if (!mounted) {
        return;
      }
      Toast.show(
        context,
        _friendlyNotificationError(e),
        type: ToastType.warning,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      Toast.show(
        context,
        'Benachrichtigung konnte nicht bestätigt werden',
        type: ToastType.warning,
      );
    } finally {
      if (mounted) {
        setState(() {
          _confirmingNotificationId = null;
        });
      }
    }
  }

  Future<void> _refreshMemberNotificationStatus() async {
    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      return;
    }

    if (!await ConnectivityService.isOnline()) {
      return;
    }

    try {
      await OfflineGroupUsersService.refreshGroupMembers(
        userEmail,
        widget.groupId,
      );
    } on UnauthorizedException {
      rethrow;
    } catch (_) {
      return;
    }
  }

  String _friendlyNotificationError(GroupNotificationApiException exception) {
    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Benachrichtigung nicht gefunden';
      default:
        final message = exception.message.trim();
        return message.isNotEmpty
            ? message
            : 'Benachrichtigung konnte nicht bestätigt werden';
    }
  }

  Widget? _buildPendingNotificationSection(ThemeData theme) {
    if (_pendingNotifications.isEmpty) {
      return null;
    }

    final colorScheme = theme.colorScheme;
    return Column(
      key: const Key('pendingGroupNotificationSection'),
      children: _pendingNotifications.map((pendingNotification) {
        final isConfirmingCurrentNotification =
            _confirmingNotificationId == pendingNotification.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            key: Key('pendingGroupNotificationCard_${pendingNotification.id}'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Erinnerung von ${pendingNotification.actorUsername}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  pendingNotification.message,
                  style: TextStyle(
                    fontSize: 15,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: Key(
                    'confirmGroupNotificationButton_${pendingNotification.id}',
                  ),
                  onPressed: _confirmingNotificationId != null
                      ? null
                      : () => _confirmNotification(pendingNotification.id),
                  icon: isConfirmingCurrentNotification
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Bring ich mit'),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openGroupSettings() async {
    await Navigator.pushNamed(
      context,
      '/groupSettings',
      arguments: widget.groupId,
    );
    if (!mounted) return;
    await _loadCounter(showLoading: false);
    await _loadGroupSettings();
  }

  Future<void> _handlePendingSyncTap(SyncProvider syncProvider) async {
    if (!syncProvider.hasPendingSync) {
      return;
    }

    if (syncProvider.isSyncing) {
      Toast.show(
        context,
        'Offene Änderungen werden gerade synchronisiert',
        type: ToastType.info,
      );
      return;
    }

    Toast.show(
      context,
      'Synchronisierung wird gestartet',
      type: ToastType.info,
    );

    final success = await syncProvider.requestSync();
    if (!mounted) return;

    Toast.show(
      context,
      success
          ? 'Offene Änderungen wurden synchronisiert'
          : 'Offene Änderungen konnten gerade nicht synchronisiert werden',
      type: success ? ToastType.success : ToastType.warning,
    );
  }

  Widget _buildPrimaryActionContent() {
    final foregroundColor = Theme.of(context).colorScheme.onPrimary;

    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedSlide(
            duration: _primaryActionTransitionDuration,
            curve: Curves.easeOutCubic,
            offset: _isSubmitting ? const Offset(0, 0.08) : Offset.zero,
            child: AnimatedOpacity(
              duration: _primaryActionTransitionDuration,
              curve: Curves.easeOutCubic,
              opacity: _isSubmitting ? 0 : 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Strich machen',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: foregroundColor,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Halten für mehrere',
                    style: TextStyle(fontSize: 14, color: foregroundColor),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSlide(
            duration: _primaryActionTransitionDuration,
            curve: Curves.easeOutCubic,
            offset: _isSubmitting ? Offset.zero : const Offset(0, -0.08),
            child: AnimatedOpacity(
              duration: _primaryActionTransitionDuration,
              curve: Curves.easeOutCubic,
              opacity: _isSubmitting ? 1 : 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: foregroundColor,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Bitte warten',
                    style: TextStyle(fontSize: 14, color: foregroundColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildPendingSyncAction(SyncProvider syncProvider) {
    if (!syncProvider.hasPendingSync) {
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.error;

    if (syncProvider.isSyncing) {
      return IconButton(
        tooltip: 'Synchronisierung offener Änderungen läuft',
        onPressed: () => _handlePendingSyncTap(syncProvider),
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: colorScheme.primary,
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Offene Änderungen synchronisieren',
      onPressed: () => _handlePendingSyncTap(syncProvider),
      icon: Icon(Icons.sync_problem_rounded, color: iconColor),
    );
  }

  void _showStrichDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: !_isSubmitting,
      builder: (context) {
        return PopScope(
          canPop: !_isSubmitting,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Anzahl',
                      labelStyle: TextStyle(color: Colors.grey[600]),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: _isSubmitting
                        ? null
                        : (_) => _handleStrichInput(controller),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _handleStrichInput(controller),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Hinzufügen'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleStrichInput(TextEditingController controller) async {
    final text = controller.text.trim();
    final value = int.tryParse(text);
    if (value == null || value <= 0) {
      Toast.show(
        context,
        'Bitte eine gültige Anzahl eingeben',
        type: ToastType.warning,
      );
      return;
    }
    final result = await _incrementStrich(value);
    if (!mounted || result == _StrichSubmitResult.failed) return;
    safePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final theme = Theme.of(context);
    final absoluteStrichCount = _strichCount.abs();
    final saldoColor = _saldoColor(theme, _strichCount);
    final saldoCountText = '$_strichCount ${_strichLabel(absoluteStrichCount)}';
    final saldoAmountText =
        '${_saldoStatusLabel(_strichCount)} · ${_formatMoney(absoluteStrichCount * _pricePerStrich)} €';
    final groupTitle = _groupName?.trim().isNotEmpty == true
        ? _groupName!
        : 'Gruppe ${widget.groupId}';
    final pendingSyncAction = _buildPendingSyncAction(syncProvider);
    final pendingNotificationSection = _buildPendingNotificationSection(theme);

    return Scaffold(
      appBar: AppBar(
        title: Text(groupTitle),
        leading: IconButton(
          icon: const Icon(Icons.group),
          onPressed: () {
            Navigator.pushNamed(
              context,
              '/groups',
              arguments: widget.groupId,
            ).then((_) {
              if (!mounted) {
                return;
              }

              unawaited(_loadPendingNotifications());
            });
          },
        ),
        actions: [
          ?pendingSyncAction,
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
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
                      onPressed: () => _loadCounter(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut laden'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 75),
                  IgnorePointer(
                    ignoring: _isSubmitting,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _incrementStrich();
                      },
                      onLongPress: _showStrichDialog,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 38,
                          horizontal: 65,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _buildPrimaryActionContent(),
                    ),
                  ),
                  const SizedBox(height: 45),
                  Center(
                    child: Text(
                      saldoCountText,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: saldoColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: Text(
                      saldoAmountText,
                      style: TextStyle(
                        fontSize: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (pendingNotificationSection != null) ...[
                    const SizedBox(height: 32),
                    pendingNotificationSection,
                  ],
                  const SizedBox(height: 65),
                  ListTile(
                    leading: const Icon(Icons.people),
                    title: const Text('Mitgliederübersicht'),
                    subtitle: const Text('Alle Mitglieder & Striche sehen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/groupUsers',
                        arguments: AppRoutes.groupArgs(
                          widget.groupId,
                          groupName: _groupNameForArgs(),
                        ),
                      ).then((_) async {
                        if (!mounted) {
                          return;
                        }

                        await _loadCounter(showLoading: false);
                        await _loadGroupSettings();
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Verlauf'),
                    subtitle: const Text('Aktivitäten anzeigen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/groupActivity',
                        arguments: AppRoutes.groupArgs(widget.groupId),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(indent: 16, endIndent: 16),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.handyman),
                    title: const Text('Gruppeneinstellungen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openGroupSettings,
                  ),
                  const SizedBox(height: 75),
                ],
              ),
            ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../providers/group_role_provider.dart';
import '../routes/app_routes.dart';
import '../services/connectivity_service.dart';
import '../services/group_counter_api_service.dart';
import '../services/http_service.dart';
import '../services/offline_group_settings_service.dart';
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

class _GroupHomePageState extends State<GroupHomePage> {
  final GroupCounterApiService _groupCounterApiService =
      GroupCounterApiService();
  static const _minimumSubmitDuration = Duration(milliseconds: 250);
  static const _primaryActionTransitionDuration = Duration(milliseconds: 220);
  int _strichCount = 0;
  double _pricePerStrich = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadErrorMessage;
  String? _groupName;
  SyncProvider? _syncProvider;
  bool _wasOnline = false;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName?.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_loadCounter());
      unawaited(_loadGroupRole());
      unawaited(_loadGroupSettings());
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
    _syncProvider?.removeListener(_handleSyncProviderChanged);
    super.dispose();
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
    await OfflineStrichService.addPendingOwnCounterIncrement(
      userEmail,
      widget.groupId,
      amount,
    );
    if (!mounted) return _StrichSubmitResult.failed;

    setState(() {
      _strichCount += amount;
      _loadErrorMessage = null;
    });
    _showSavedToast(amount);
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

  void _showSavedToast(int amount) {
    final message = switch (amount) {
      1 => 'Strich gespeichert',
      _ => '$amount Striche gespeichert',
    };

    Toast.show(
      context,
      message,
      type: ToastType.success,
      actionLabel: 'Rückgängig',
      onActionTap: () {},
    );
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
    final currency = (_strichCount * _pricePerStrich).toStringAsFixed(2);
    final groupTitle = _groupName?.trim().isNotEmpty == true
        ? _groupName!
        : 'Gruppe ${widget.groupId}';
    final pendingSyncAction = _buildPendingSyncAction(syncProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(groupTitle),
        leading: IconButton(
          icon: const Icon(Icons.group),
          onPressed: () => Navigator.pushNamed(
            context,
            '/groups',
            arguments: widget.groupId,
          ),
        ),
        actions: [
          if (pendingSyncAction != null) pendingSyncAction,
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
                      '$_strichCount ${_strichCount == 1 ? 'Strich' : 'Striche'}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: Text(
                      '$currency €',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ),
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

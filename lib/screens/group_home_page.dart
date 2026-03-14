import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../services/group_counter_api_service.dart';
import '../services/http_service.dart';
import '../services/offline_strich_service.dart';
import '../widgets/toast.dart';
import '../providers/auth_provider.dart';
import '../utils/navigation_helper.dart';

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
  int _strichCount = 0;
  int _pendingCount = 0;
  final double _pricePerStrich = 1.5;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isShowingOfflineData = false;
  String? _loadErrorMessage;
  SyncProvider? _syncProvider;
  bool _wasOnline = false;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadCounter();
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
      _loadCounter();
    }
  }

  Future<void> _loadCounter() async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    if (userEmail == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Counter konnte nicht geladen werden';
      });
      return;
    }

    try {
      if (syncProvider.isAppOnline) {
        await _groupCounterApiService.syncPendingCounterOperations(
          userEmail,
          groupId: widget.groupId,
        );
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
        _pendingCount = pendingCount;
        _isLoading = false;
        _isShowingOfflineData = pendingCount > 0;
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

  Future<bool> _incrementStrich([int amount = 1]) async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

    if (userEmail == null) {
      return false;
    }

    setState(() {
      _isSubmitting = true;
    });

    if (!syncProvider.isAppOnline) {
      return _storeOfflineIncrement(userEmail, amount);
    }

    try {
      final counter = await _groupCounterApiService.incrementMyGroupCounter(
        widget.groupId,
        amount,
      );
      await OfflineStrichService.saveLastOnlineCounter(
        userEmail,
        widget.groupId,
        counter.count,
      );
      if (!mounted) return false;

      setState(() {
        _strichCount = counter.count;
        _pendingCount = 0;
        _isShowingOfflineData = false;
      });
      return true;
    } on UnauthorizedException {
      return false;
    } on GroupCounterApiException catch (e) {
      if (e.message == 'Netzwerkfehler') {
        return _storeOfflineIncrement(userEmail, amount);
      }
      if (!mounted) return false;
      Toast.show(context, e.message);
    } catch (_) {
      if (!mounted) return false;
      Toast.show(context, 'Gruppen-Counter konnte nicht aktualisiert werden');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }

    return false;
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
      _pendingCount = pendingCount;
      _isLoading = false;
      _isShowingOfflineData = true;
      _loadErrorMessage = null;
    });

    if (lastOnlineCount == 0 && pendingCount == 0) {
      setState(() {
        _loadErrorMessage = fallbackErrorMessage;
      });
    }
  }

  Future<bool> _storeOfflineIncrement(String userEmail, int amount) async {
    await OfflineStrichService.addPendingOwnCounterIncrement(
      userEmail,
      widget.groupId,
      amount,
    );
    if (!mounted) return false;

    setState(() {
      _strichCount += amount;
      _pendingCount += amount;
      _isShowingOfflineData = true;
      _loadErrorMessage = null;
    });
    Toast.show(context, 'Striche offline gespeichert', type: ToastType.warning);
    return true;
  }

  void _showStrichDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Anzahl',
                    labelStyle: TextStyle(color: Colors.grey[600]),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleStrichInput(controller),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _handleStrichInput(controller),
                  child: const Text('Hinzufügen'),
                ),
              ],
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
    final success = await _incrementStrich(value);
    if (!mounted || !success) return;
    safePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();
    final currency = (_strichCount * _pricePerStrich).toStringAsFixed(2);
    final buttonLabel = _isSubmitting ? 'Speichert...' : 'Strich machen';
    final statusText = _buildStatusText(syncProvider);
    final groupTitle = widget.groupName?.trim().isNotEmpty == true
        ? widget.groupName!
        : 'Gruppe ${widget.groupId}';

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
                      onPressed: _loadCounter,
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
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _incrementStrich(),
                    onLongPress: _isSubmitting ? null : _showStrichDialog,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 38,
                        horizontal: 65,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          buttonLabel,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isSubmitting ? 'Bitte warten' : 'Halten für mehrere',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
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
                  if (statusText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
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
                        arguments: {
                          'groupId': widget.groupId,
                          if (widget.groupName != null)
                            'groupName': widget.groupName,
                        },
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Verlauf'),
                    subtitle: const Text('Aktivitäten anzeigen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final currentUserId =
                          context.read<AuthProvider>().userEmail ?? '';
                      Navigator.of(context).pushNamed(
                        '/groupActivity',
                        arguments: {
                          'groupId': widget.groupId,
                          if (widget.groupName != null)
                            'groupName': widget.groupName,
                          'currentUserId': currentUserId,
                        },
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
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/groupSettings',
                        arguments: widget.groupId,
                      );
                    },
                  ),
                  const SizedBox(height: 75),
                ],
              ),
            ),
    );
  }

  String? _buildStatusText(SyncProvider syncProvider) {
    if (_isSubmitting) {
      return 'Counter wird gespeichert';
    }

    if (_pendingCount > 0 && syncProvider.isSyncing) {
      return '$_pendingCount Striche werden synchronisiert';
    }

    if (_pendingCount > 0 && !syncProvider.isAppOnline) {
      return '$_pendingCount Striche warten auf Synchronisierung';
    }

    if (_pendingCount > 0) {
      return '$_pendingCount lokale Anderungen noch offen';
    }

    if (_isShowingOfflineData && !syncProvider.isAppOnline) {
      return 'Offline-Stand aus lokalem Speicher';
    }

    return null;
  }
}

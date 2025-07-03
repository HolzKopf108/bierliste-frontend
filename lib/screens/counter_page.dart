import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/counter_api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../services/offline_strich_service.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _counter = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCounter();
  }

  Future<void> _loadCounter() async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

    if (userEmail == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (syncProvider.isAppOnline) {
      await CounterApiService().syncPendingStriche(userEmail);

      final result = await CounterApiService().fetchCounter();
      if (result != null) {
        await OfflineStrichService.saveLastOnlineCounter(userEmail, result.count);
        setState(() => _counter = result.count);
      }
    } else {
      final last = await OfflineStrichService.getLastOnlineCounter(userEmail);
      final pending = await OfflineStrichService.getPendingSum(userEmail);
      setState(() => _counter = last + pending);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _incrementCounter() async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

    setState(() => _counter++);

    if (userEmail == null) return;

    if (!syncProvider.isAppOnline) {
      await OfflineStrichService.addPendingStriche(userEmail, 1);
      return;
    }

    final success = await CounterApiService().updateCounter(1);
    if (!success) {
      await OfflineStrichService.addPendingStriche(userEmail, 1);
    } else {
      final result = await CounterApiService().fetchCounter();
      if (result != null) {
        await OfflineStrichService.saveLastOnlineCounter(userEmail, result.count);
        setState(() => _counter = result.count);
      }
    }
  }

  Future<void> _syncStriche() async {
    final authProvider = context.read<AuthProvider>();
    final syncProvider = context.read<SyncProvider>();
    final userEmail = authProvider.userEmail;

    if (userEmail == null) return;

    final total = await OfflineStrichService.getPendingSum(userEmail);
    if (total == 0) return;

    syncProvider.setIsSyncing(true);
    final success = await CounterApiService().updateCounter(total);
    syncProvider.setIsSyncing(false);

    if (success) {
      await OfflineStrichService.clearPendingStriche(userEmail);

      final result = await CounterApiService().fetchCounter();
      if (result != null) {
        await OfflineStrichService.saveLastOnlineCounter(userEmail, result.count);
        setState(() => _counter = result.count);
      }
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Striche konnten nicht synchronisiert werden'),
          content: const Text("Versuche es später noch einmal"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    }
  }

  void _updateAutoSyncEnabled(SyncProvider syncProvider) async {
    await syncProvider.setAutoSyncEnabled(!syncProvider.isAutoSyncEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<SyncProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bier-Zähler'),
        leading: IconButton(
          icon: const Icon(Icons.group),
          onPressed: () {
            Navigator.pushNamed(context, '/groups');
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              syncProvider.isAutoSyncEnabled
                  ? (syncProvider.isAppOnline ? Icons.cloud : Icons.cloud_off)
                  : Icons.sync_disabled,
            ),
            onPressed: () {
              _updateAutoSyncEnabled(syncProvider);
            },
            tooltip: syncProvider.isAutoSyncEnabled
                ? 'Automatische Synchronisation aktiv'
                : 'Automatische Synchronisation deaktiviert',
          ),
          if (!syncProvider.isAutoSyncEnabled)
            IconButton(
              icon: syncProvider.isSyncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              onPressed: syncProvider.isSyncing ? null : _syncStriche,
              tooltip: 'Manuell synchronisieren',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _incrementCounter,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(40),
                  shape: const CircleBorder(),
                ),
                child: Text(
                  '$_counter',
                  style: const TextStyle(fontSize: 32),
                ),
              ),
      ),
    );
  }
}

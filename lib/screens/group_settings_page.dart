import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/offline_group_settings_service.dart';
import '../services/group_api_service.dart';
import '../services/http_service.dart';
import '../utils/navigation_helper.dart';
import '../widgets/toast.dart';

class GroupSettingsPage extends StatefulWidget {
  final int groupId;
  const GroupSettingsPage({super.key, required this.groupId});

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  final GroupApiService _groupApiService = GroupApiService();
  final _groupNameController = TextEditingController();
  final _groupIdController = TextEditingController();

  bool _isLoading = true;
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    _groupIdController.text = widget.groupId.toString();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, 'Gruppe konnte nicht geladen werden');
      return;
    }

    final cachedGroup = await OfflineGroupSettingsService.getGroup(
      userEmail,
      widget.groupId,
    );
    if (!mounted) return;

    if (cachedGroup != null) {
      setState(() {
        _groupNameController.text = cachedGroup.name;
        _isLoading = false;
      });
    }

    try {
      final group = await OfflineGroupSettingsService.refreshGroup(
        userEmail,
        widget.groupId,
      );
      if (!mounted) return;
      setState(() {
        _groupNameController.text = group.name;
        _isLoading = false;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() => _isLoading = false);
    } on GroupApiException catch (e) {
      if (cachedGroup != null) {
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, e.message);
    } catch (_) {
      if (cachedGroup != null) {
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, 'Fehler beim Laden der Gruppe');
    }
  }

  Future<void> _leaveGroup() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);

    try {
      await _groupApiService.leaveGroup(widget.groupId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gruppe erfolgreich verlassen')),
      );
      safePushNamedAndRemoveUntil(context, '/groups');
    } on UnauthorizedException {
      return;
    } on GroupApiException catch (e) {
      if (!mounted) return;
      Toast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      Toast.show(context, 'Fehler beim Verlassen der Gruppe');
    } finally {
      if (mounted) {
        setState(() => _isLeaving = false);
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gruppeneinstellungen')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Gruppeneinstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _groupNameController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Gruppenname',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Weitere Gruppeneinstellungen sind aktuell im Backend noch nicht verfügbar.',
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Gruppe verlassen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _isLeaving ? null : _leaveGroup,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _groupIdController,
            readOnly: true,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: const InputDecoration(
              labelText: 'Gruppen-ID',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

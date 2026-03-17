import 'dart:async';

import 'package:bierliste/models/group_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/money_input_formatter.dart';
import '../services/offline_group_settings_service.dart';
import '../services/group_api_service.dart';
import '../services/group_settings_api_service.dart';
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
  final _formKey = GlobalKey<FormState>();
  final GroupApiService _groupApiService = GroupApiService();
  final _groupNameController = TextEditingController();
  final _pricePerStrichController = TextEditingController();
  final _groupIdController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLeaving = false;
  bool _onlyWartsCanBookForOthers = false;

  @override
  void initState() {
    super.initState();
    _groupIdController.text = widget.groupId.toString();
    _loadGroupSettings();
  }

  Future<void> _loadGroupSettings() async {
    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, 'Gruppeneinstellungen konnten nicht geladen werden');
      return;
    }

    final cachedGroupSettings =
        await OfflineGroupSettingsService.getGroupSettings(
          userEmail,
          widget.groupId,
        );
    if (!mounted) return;

    if (cachedGroupSettings != null) {
      setState(() {
        _applyGroupSettings(cachedGroupSettings);
        _isLoading = false;
      });
    }

    try {
      final groupSettings =
          await OfflineGroupSettingsService.refreshGroupSettings(
            userEmail,
            widget.groupId,
          );
      if (!mounted) return;
      setState(() {
        _applyGroupSettings(groupSettings);
        _isLoading = false;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() => _isLoading = false);
    } on GroupSettingsApiException catch (e) {
      if (cachedGroupSettings != null) {
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, e.message);
    } on TimeoutException {
      if (cachedGroupSettings != null) {
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, 'Gruppeneinstellungen konnten nicht geladen werden');
    } catch (_) {
      if (cachedGroupSettings != null) {
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      Toast.show(context, 'Fehler beim Laden der Gruppe');
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    final userEmail = context.read<AuthProvider>().userEmail;
    if (userEmail == null) {
      Toast.show(
        context,
        'Gruppeneinstellungen konnten nicht gespeichert werden',
      );
      return;
    }

    final pricePerStrich = _parsePricePerStrich(
      _pricePerStrichController.text.trim(),
    );
    if (pricePerStrich == null) {
      Toast.show(context, 'Preis pro Strich ist ungültig');
      return;
    }

    setState(() => _isSaving = true);

    final payload = GroupSettings(
      name: _groupNameController.text.trim(),
      pricePerStrich: pricePerStrich,
      onlyWartsCanBookForOthers: _onlyWartsCanBookForOthers,
    );

    try {
      final updatedSettings =
          await OfflineGroupSettingsService.updateGroupSettings(
            userEmail,
            widget.groupId,
            payload,
          );

      if (!mounted) return;
      setState(() {
        _applyGroupSettings(updatedSettings);
      });
      Toast.show(
        context,
        'Gruppeneinstellungen gespeichert',
        type: ToastType.success,
      );
    } on UnauthorizedException {
      return;
    } on GroupSettingsApiException catch (e) {
      if (!mounted) return;
      Toast.show(context, e.message);
    } on TimeoutException {
      if (!mounted) return;
      Toast.show(
        context,
        'Gruppeneinstellungen konnten nicht gespeichert werden',
      );
    } catch (_) {
      if (!mounted) return;
      Toast.show(context, 'Fehler beim Speichern der Gruppeneinstellungen');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _applyGroupSettings(GroupSettings settings) {
    _groupNameController.text = settings.name;
    _pricePerStrichController.text = settings.pricePerStrich
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    _onlyWartsCanBookForOthers = settings.onlyWartsCanBookForOthers;
  }

  double? _parsePricePerStrich(String value) {
    final normalized = value.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized);
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
    _pricePerStrichController.dispose();
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _groupNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Gruppenname',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.length < 3) {
                  return 'Gruppenname muss mindestens 3 Zeichen lang sein';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _pricePerStrichController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[MoneyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Preis pro Strich',
                border: OutlineInputBorder(),
                suffixText: 'EUR',
              ),
              validator: (value) {
                final parsed = _parsePricePerStrich(value?.trim() ?? '');
                if (parsed == null) {
                  return 'Preis pro Strich ist ungültig';
                }
                if (parsed < 0) {
                  return 'Preis pro Strich darf nicht negativ sein';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur Warte dürfen für andere buchen'),
              value: _onlyWartsCanBookForOthers,
              onChanged: (value) {
                setState(() => _onlyWartsCanBookForOthers = value);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('Speichern'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _isSaving || _isLeaving ? null : _saveSettings,
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
              onPressed: _isLeaving || _isSaving ? null : _leaveGroup,
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
      ),
    );
  }
}

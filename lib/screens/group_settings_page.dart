import 'dart:async';

import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/group_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/group_role_provider.dart';
import '../providers/sync_provider.dart';
import '../services/connectivity_service.dart';
import '../services/offline_group_settings_service.dart';
import '../services/group_api_service.dart';
import '../services/group_settings_api_service.dart';
import '../services/http_service.dart';
import '../utils/navigation_helper.dart';
import '../utils/money_input_formatter.dart';
import '../widgets/toast.dart';

class _DecimalSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalizedText = newValue.text.replaceAll('.', ',');
    if (normalizedText == newValue.text) {
      return newValue;
    }

    return TextEditingValue(
      text: normalizedText,
      selection: TextSelection.collapsed(
        offset: newValue.selection.baseOffset.clamp(0, normalizedText.length),
      ),
    );
  }
}

class _GroupSettingsPriceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final commaIndex = text.indexOf(',');

    if (commaIndex < 0) {
      if (text.length <= 8) {
        return newValue;
      }

      return TextEditingValue(
        text: text.substring(0, 8),
        selection: const TextSelection.collapsed(offset: 8),
      );
    }

    final integerPart = text.substring(0, commaIndex);
    final decimalPart = text.substring(commaIndex + 1);
    final limitedIntegerPart = integerPart.length > 8
        ? integerPart.substring(0, 8)
        : integerPart;
    final limitedDecimalPart = decimalPart.length > 2
        ? decimalPart.substring(0, 2)
        : decimalPart;
    final limitedText = '$limitedIntegerPart,$limitedDecimalPart';

    return TextEditingValue(
      text: limitedText,
      selection: TextSelection.collapsed(offset: limitedText.length),
    );
  }
}

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
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
    _groupIdController.text = widget.groupId.toString();
    _loadGroupSettings();
  }

  Future<void> _loadGroupSettings() async {
    final userEmail = context.read<AuthProvider>().userEmail;
    final groupRoleProvider = context.read<GroupRoleProvider>();

    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    if (userEmail == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Gruppeneinstellungen konnten nicht geladen werden';
      });
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
        _loadErrorMessage = null;
      });
    }

    unawaited(
      groupRoleProvider.loadRole(userEmail, widget.groupId, forceRefresh: true),
    );

    if (!await ConnectivityService.isOnline()) {
      if (cachedGroupSettings != null) {
        return;
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Keine Verbindung';
      });
      return;
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
        _loadErrorMessage = null;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() => _isLoading = false);
    } on GroupSettingsApiException catch (e) {
      if (cachedGroupSettings != null) {
        if (!mounted) return;
        Toast.show(context, _friendlyLoadErrorMessage(e));
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = _friendlyLoadErrorMessage(e);
      });
    } on TimeoutException {
      if (cachedGroupSettings != null) {
        if (!mounted) return;
        Toast.show(context, 'Keine Verbindung');
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Keine Verbindung';
      });
    } catch (_) {
      if (cachedGroupSettings != null) {
        if (!mounted) return;
        Toast.show(context, 'Keine Verbindung');
        return;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = 'Keine Verbindung';
      });
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    final userEmail = context.read<AuthProvider>().userEmail;
    final groupRoleProvider = context.read<GroupRoleProvider>();
    final syncProvider = context.read<SyncProvider>();
    final ownRole = groupRoleProvider.roleForGroup(widget.groupId);
    if (userEmail == null) {
      Toast.show(
        context,
        'Gruppeneinstellungen konnten nicht gespeichert werden',
      );
      return;
    }

    if (ownRole != GroupMemberRole.wart) {
      Toast.show(context, 'Keine Berechtigung', type: ToastType.warning);
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
      final result = await OfflineGroupSettingsService.updateGroupSettings(
        userEmail,
        widget.groupId,
        payload,
      );

      if (!mounted) return;
      setState(() {
        _applyGroupSettings(result.groupSettings);
        _loadErrorMessage = null;
      });

      if (result.errorMessage != null) {
        Toast.show(context, result.errorMessage!, type: ToastType.warning);
      } else if (result.hasPendingSync) {
        Toast.show(
          context,
          'Gruppeneinstellungen lokal gespeichert',
          type: ToastType.success,
        );
      } else {
        Toast.show(
          context,
          'Gruppeneinstellungen gespeichert',
          type: ToastType.success,
        );
      }

      if (result.hasPendingSync) {
        unawaited(syncProvider.markPendingSync());
      } else if (result.shouldReloadUi) {
        unawaited(groupRoleProvider.refreshRole(userEmail, widget.groupId));
      }
    } on UnauthorizedException {
      return;
    } on GroupSettingsApiException catch (e) {
      if (!mounted) return;
      Toast.show(
        context,
        _friendlySaveErrorMessage(e),
        type: e.statusCode == 403 || e.statusCode == 404
            ? ToastType.warning
            : ToastType.error,
      );
      if (e.statusCode == 403) {
        unawaited(groupRoleProvider.refreshRole(userEmail, widget.groupId));
      }
    } on TimeoutException {
      if (!mounted) return;
      Toast.show(
        context,
        'Gruppeneinstellungen lokal gespeichert',
        type: ToastType.success,
      );
      unawaited(syncProvider.markPendingSync());
    } catch (_) {
      if (!mounted) return;
      Toast.show(
        context,
        'Gruppeneinstellungen konnten nicht gespeichert werden',
      );
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
    final normalized = value.trim().replaceAll('.', ',');
    if (!_isValidPricePerStrichInput(normalized)) {
      return null;
    }

    final asDouble = double.tryParse(normalized.replaceAll(',', '.'));
    if (asDouble == null || asDouble < 0) {
      return null;
    }

    return asDouble;
  }

  bool _isValidPricePerStrichInput(String value) {
    return RegExp(r'^\d{1,8}(,\d{0,2})?$').hasMatch(value);
  }

  String _friendlyLoadErrorMessage(GroupSettingsApiException exception) {
    if (_isNetworkError(exception)) {
      return 'Keine Verbindung';
    }

    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Gruppe nicht gefunden / kein Zugriff';
      default:
        return exception.message;
    }
  }

  String _friendlySaveErrorMessage(GroupSettingsApiException exception) {
    if (_isNetworkError(exception)) {
      return 'Keine Verbindung';
    }

    switch (exception.statusCode) {
      case 403:
        return 'Keine Berechtigung';
      case 404:
        return 'Gruppe nicht gefunden / kein Zugriff';
      default:
        return exception.message;
    }
  }

  String? _validatePricePerStrich(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Preis pro Strich darf nicht leer sein';
    }

    final normalized = trimmed.replaceAll('.', ',');
    if (!_isValidPricePerStrichInput(normalized)) {
      return 'Maximal 8 Stellen vor dem Komma und 2 nach dem Komma';
    }

    final parsed = _parsePricePerStrich(normalized);
    if (parsed == null) {
      return 'Preis pro Strich ist ungültig';
    }
    if (parsed < 0) {
      return 'Preis pro Strich darf nicht negativ sein';
    }

    return null;
  }

  bool _isNetworkError(GroupSettingsApiException exception) {
    final message = exception.message.trim().toLowerCase();
    return exception.statusCode == null &&
        (message == 'netzwerkfehler' || message.contains('timeout'));
  }

  bool _isReadOnly(bool canEditSettings) {
    return !canEditSettings || _isSaving || _isLeaving;
  }

  bool _isSaveDisabled(bool canEditSettings, bool isRoleLoading) {
    return !canEditSettings || isRoleLoading || _isSaving || _isLeaving;
  }

  Widget _buildPermissionHint(bool isRoleLoading, bool canEditSettings) {
    if (isRoleLoading || canEditSettings) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Du kannst die Einstellungen sehen, aber nur Bierlistenwarte dürfen sie aendern.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleLoadingHint(bool isRoleLoading) {
    if (!isRoleLoading) {
      return const SizedBox.shrink();
    }

    return const Padding(
      padding: EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('Berechtigung wird geprüft')),
        ],
      ),
    );
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
    final groupRoleProvider = context.watch<GroupRoleProvider>();
    final ownRole = groupRoleProvider.roleForGroup(widget.groupId);
    final canEditSettings = ownRole == GroupMemberRole.wart;
    final isRoleLoading = groupRoleProvider.isLoadingForGroup(widget.groupId);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gruppeneinstellungen')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadErrorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gruppeneinstellungen')),
        body: Center(
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
                  onPressed: _loadGroupSettings,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut laden'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gruppeneinstellungen')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRoleLoadingHint(isRoleLoading),
            _buildPermissionHint(isRoleLoading, canEditSettings),
            TextFormField(
              controller: _groupNameController,
              textInputAction: TextInputAction.next,
              readOnly: _isReadOnly(canEditSettings),
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
              readOnly: _isReadOnly(canEditSettings),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                _DecimalSeparatorInputFormatter(),
                MoneyInputFormatter(),
                _GroupSettingsPriceInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Preis pro Strich',
                border: OutlineInputBorder(),
                suffixText: 'EUR',
              ),
              validator: _validatePricePerStrich,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur Bierlistenwarte dürfen für andere buchen'),
              value: _onlyWartsCanBookForOthers,
              onChanged: _isReadOnly(canEditSettings)
                  ? null
                  : (value) {
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
              onPressed: _isSaveDisabled(canEditSettings, isRoleLoading)
                  ? null
                  : _saveSettings,
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

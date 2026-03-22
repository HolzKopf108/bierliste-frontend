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

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLeaving = false;
  bool _onlyWartsCanBookForOthers = false;
  bool _allowArbitraryMoneySettlements = false;
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
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
      allowArbitraryMoneySettlements: _allowArbitraryMoneySettlements,
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
    _allowArbitraryMoneySettlements = settings.allowArbitraryMoneySettlements;
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

  String get _moneySettlementHelpMessage =>
      'Wenn aktiviert, dürfen Bierlistenwarte beliebige Geldbeträge abziehen. '
      'Es wird immer auf volle Striche abgerundet und der Restbetrag ignoriert. '
      'Beispiel: 2,50 EUR bei 1,00 EUR pro Strich zieht 2 Striche ab. '
      'Wenn deaktiviert, sind nur Vielfache des Preises pro Strich erlaubt.';

  String get _onlyWartsCanBookForOthersHelpMessage =>
      'Wenn aktiviert, dürfen nur Bierlistenwarte für andere Mitglieder '
      'buchen. Wenn deaktiviert, dürfen alle Mitglieder auch für andere '
      'buchen.';

  Future<void> _showOnlyWartsCanBookForOthersHelpDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hinweis zu Buchungen für andere'),
          content: Text(_onlyWartsCanBookForOthersHelpMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMoneySettlementHelpDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hinweis zu Geldabzügen'),
          content: Text(_moneySettlementHelpMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingInfoButton(VoidCallback onPressed) {
    return IconButton(
      tooltip: 'Hinweis anzeigen',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 20, height: 20),
      splashRadius: 18,
      icon: Icon(
        Icons.info_outline,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildSwitchSettingTile({
    required bool canEditSettings,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onInfoTap,
  }) {
    final readOnly = _isReadOnly(canEditSettings);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minLeadingWidth: 24,
        leading: _buildSettingInfoButton(onInfoTap),
        title: Text(title),
        trailing: Switch(value: value, onChanged: readOnly ? null : onChanged),
        onTap: readOnly
            ? null
            : () {
                onChanged(!value);
              },
      ),
    );
  }

  Widget _buildBookingForOthersTile(bool canEditSettings) {
    return _buildSwitchSettingTile(
      canEditSettings: canEditSettings,
      title: 'Nur Bierlistenwarte dürfen für andere buchen',
      value: _onlyWartsCanBookForOthers,
      onChanged: (value) {
        setState(() => _onlyWartsCanBookForOthers = value);
      },
      onInfoTap: _showOnlyWartsCanBookForOthersHelpDialog,
    );
  }

  Widget _buildMoneySettlementTile(bool canEditSettings) {
    return _buildSwitchSettingTile(
      canEditSettings: canEditSettings,
      title: 'Beliebige Geldbeträge für Abzüge erlauben',
      value: _allowArbitraryMoneySettlements,
      onChanged: (value) {
        setState(() => _allowArbitraryMoneySettlements = value);
      },
      onInfoTap: _showMoneySettlementHelpDialog,
    );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupRoleProvider = context.watch<GroupRoleProvider>();
    final ownRole = groupRoleProvider.roleForGroup(widget.groupId);
    final canEditSettings = ownRole == GroupMemberRole.wart;
    final isRoleLoading = groupRoleProvider.isLoadingForGroup(widget.groupId);
    final theme = Theme.of(context);

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
            const SizedBox(height: 5),
            _buildRoleLoadingHint(isRoleLoading),
            const SizedBox(height: 30),
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
            const SizedBox(height: 30),
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
              ],
              decoration: const InputDecoration(
                labelText: 'Preis pro Strich',
                border: OutlineInputBorder(),
                suffixText: 'EUR',
              ),
              validator: _validatePricePerStrich,
            ),
            const SizedBox(height: 30),
            _buildBookingForOthersTile(canEditSettings),
            const SizedBox(height: 20),
            _buildMoneySettlementTile(canEditSettings),
            const SizedBox(height: 30),
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
            const SizedBox(height: 80),
            Row(
              children: const [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Gefahrenbereich',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 40),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Gruppe verlassen',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Du verlässt diese Gruppe sofort. Dieser Vorgang kann nicht rückgängig gemacht werden.',
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('GRUPPE VERLASSEN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isLeaving || _isSaving ? null : _leaveGroup,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Gruppen-ID: ${widget.groupId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

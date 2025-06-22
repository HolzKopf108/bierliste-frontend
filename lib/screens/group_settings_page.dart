import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/money_input_formatter.dart';
import '../utils/navigation_helper.dart';

class GroupSettingsPage extends StatefulWidget {
  final int groupId;
  const GroupSettingsPage({Key? key, required this.groupId}) : super(key: key);

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  final _groupNameController = TextEditingController();
  final _priceController = TextEditingController();

  bool _onlyManagersCanAddStriche = false;
  bool _onlyManagersCanDeposit = false;
  bool _isManager = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroupSettings();
  }

  Future<void> _loadGroupSettings() async {
    final url = Uri.parse('https://your.backend.api/groups/${widget.groupId}/settings');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _groupNameController.text = data['name'];
        _priceController.text = data['pricePerStrich'].toString();
        _onlyManagersCanAddStriche = data['onlyManagersCanAddStriche'];
        _onlyManagersCanDeposit = data['onlyManagersCanDeposit'];
        _isManager = data['isManager'];
        _isLoading = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Laden der Einstellungen')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final payload = json.encode({
      'name': _groupNameController.text.trim(),
      'pricePerStrich': double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0.0,
      'onlyManagersCanAddStriche': _onlyManagersCanAddStriche,
      'onlyManagersCanDeposit': _onlyManagersCanDeposit,
    });
    final url = Uri.parse('https://your.backend.api/groups/${widget.groupId}/settings');
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
      safePop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Speichern der Einstellungen')),
      );
    }
  }

  Future<void> _leaveGroup() async {
    final url = Uri.parse('https://your.backend.api/groups/${widget.groupId}/leave');
    final response = await http.post(url);

    if (!mounted) return;

    if (response.statusCode == 200) {
      safePop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Verlassen der Gruppe')),
      );
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          // 1. Gruppenname
          TextField(
            controller: _groupNameController,
            enabled: _isManager,
            decoration: const InputDecoration(
              labelText: 'Gruppenname',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Preis pro Strich
          TextField(
            controller: _priceController,
            enabled: _isManager,
            decoration: const InputDecoration(
              labelText: 'Preis pro Strich',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [MoneyInputFormatter()],
          ),
          const SizedBox(height: 20),

          // 3. Striche für andere
          SwitchListTile(
            title: const Text('Nur Bierlistenwarte können Striche für andere machen'),
            value: _onlyManagersCanAddStriche,
            onChanged: _isManager ? (val) => setState(() => _onlyManagersCanAddStriche = val) : null,
          ),

          // 4. Geld einzahlen
          SwitchListTile(
            title: const Text('Nur Bierlistenwarte können Geld einzahlen'),
            value: _onlyManagersCanDeposit,
            onChanged: _isManager ? (val) => setState(() => _onlyManagersCanDeposit = val) : null,
          ),

          const SizedBox(height: 30),

          // 5. Speichern (immer sichtbar, aber nur aktiv für Manager)
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _isManager ? _saveSettings : null,
          ),

          const SizedBox(height: 32),

          // Gruppe verlassen (für alle verfügbar)
          ElevatedButton.icon(
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Gruppe verlassen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _leaveGroup,
          ),
        ],
      ),
    );
  }
}

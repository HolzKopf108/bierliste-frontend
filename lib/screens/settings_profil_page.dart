import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';

class SettingsProfilPage extends StatefulWidget {
  const SettingsProfilPage({super.key});

  @override
  State<SettingsProfilPage> createState() => _SettingsProfilPageState();
}

class _SettingsProfilPageState extends State<SettingsProfilPage> {
  final _displayNameController = TextEditingController();
  final _password1Controller = TextEditingController();
  final _password2Controller = TextEditingController();

  bool _obscurePw1 = true;
  bool _obscurePw2 = true;

  String _username = 'benutzer123'; // Wird vom Backend geladen
  String _originalDisplayName = 'Max Mustermann';

  @override
  void initState() {
    super.initState();
    // ⚙️ Hier echten User laden:
    _displayNameController.text = _originalDisplayName;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _password1Controller.dispose();
    _password2Controller.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final newDisplayName = _displayNameController.text.trim();
    final pw1 = _password1Controller.text.trim();
    final pw2 = _password2Controller.text.trim();

    bool updated = false;

    if (newDisplayName != _originalDisplayName) {
      // TODO: Anfrage an Backend senden
      //await updateDisplayName(newDisplayName);
      updated = true;
    }

    if (pw1.isNotEmpty || pw2.isNotEmpty) {
      if (pw1 != pw2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwörter stimmen nicht überein')),
        );
        return;
      }

      // TODO: Anfrage an Backend senden
      //await updatePassword(pw1);
      updated = true;
    }

    if (updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Center(child: Text('Profil aktualisiert')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _originalDisplayName = newDisplayName;
      _password1Controller.clear();
      _password2Controller.clear();
      safePop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Center(child: Text('Keine Änderungen vorgenommen')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil bearbeiten')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 40),

          // Benutzername (read only)
          TextField(
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Benutzername',
              border: const OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _username),
          ),

          const SizedBox(height: 20),

          // Anzeigename (editierbar)
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Anzeigename',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 40),

          // Neues Passwort
          TextField(
            controller: _password1Controller,
            obscureText: _obscurePw1,
            decoration: InputDecoration(
              labelText: 'Neues Passwort',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePw1 ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePw1 = !_obscurePw1),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Passwort wiederholen
          TextField(
            controller: _password2Controller,
            obscureText: _obscurePw2,
            decoration: InputDecoration(
              labelText: 'Passwort bestätigen',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePw2 ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePw2 = !_obscurePw2),
              ),
            ),
          ),

          const SizedBox(height: 30),
          const Divider(indent: 16, endIndent: 16),
          const SizedBox(height: 30),

          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _saveProfile,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

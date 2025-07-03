import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:bierliste/services/token_service.dart';
import 'package:bierliste/services/user_service.dart';
import 'package:bierliste/utils/navigation_helper.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsProfilPage extends StatefulWidget {
  const SettingsProfilPage({super.key});

  @override
  State<SettingsProfilPage> createState() => _SettingsProfilPageState();
}

class _SettingsProfilPageState extends State<SettingsProfilPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _password1Controller = TextEditingController();
  final _password2Controller = TextEditingController();

  bool get _isGoogleUser => context.read<UserProvider>().user?.googleUser ?? false;

  bool _obscurePw1 = true;
  bool _obscurePw2 = true;

  String _originalUsername = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  void _initializeUser() async {
    final userProvider = context.read<UserProvider>();
    await userProvider.loadUser();

    final user = userProvider.user;
    if (user != null) {
      _originalUsername = user.username;
      _emailController.text = await TokenService.getUserEmail() ?? user.email;
      _usernameController.text = user.username;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _password1Controller.dispose();
    _password2Controller.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final newUsername = _usernameController.text.trim();
    final newPassword = _password1Controller.text.trim();

    setState(() => _isLoading = true);

    final userProvider = context.read<UserProvider>();
    bool updated = false;

    if (newUsername != _originalUsername) {
      await userProvider.updateUsername(newUsername);
      updated = true;
    }

    if (!_isGoogleUser && newPassword.isNotEmpty) {
      final error = await UserService.updatePassword(newPassword);
      if (error != null) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        Toast.show(context, error);
        return;
      }
      updated = true;
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (updated) {
      _originalUsername = newUsername;
      _password1Controller.clear();
      _password2Controller.clear();
      Toast.show(context, 'Profil aktualisiert');
      safePop(context);
    } else {
      Toast.show(context, 'Keine Änderungen vorgenommen');
    }
  }

  void _showDeleteAccountDialog() {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konto löschen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '⚠️ Dieser Vorgang kann nicht rückgängig gemacht werden.\n'
                'Um dein Konto zu löschen, gib „LÖSCHEN“ ein.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  labelText: 'Bestätigung',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Abbrechen'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete),
              label: const Text('Löschen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (confirmController.text.trim() == 'LÖSCHEN') {
                  Navigator.of(context).pop();
                  final error = await UserService.deleteAccount(context.read<AuthProvider>());
                  if (!context.mounted) return;
                  if (error != null) {
                    Toast.show(context, error);
                  }
                } else {
                  Toast.show(context, 'Falsche Eingabe. Bitte „LÖSCHEN“ eingeben.');
                }
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil bearbeiten')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 40),

            TextFormField(
              controller: _emailController,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'E-Mail',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Benutzername',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.length < 3) {
                  return 'Benutzername zu kurz';
                }
                return null;
              },
            ),

            const SizedBox(height: 40),

            TextFormField(
              controller: _password1Controller,
              obscureText: _obscurePw1,
              enabled: !_isGoogleUser,
              decoration: InputDecoration(
                labelText: 'Neues Passwort',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePw1 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePw1 = !_obscurePw1),
                ),
              ),
              validator: (value) {
                if (value != null && value.isNotEmpty && value.length < 8) {
                  return 'Passwort muss mindestens 8 Zeichen lang sein';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            TextFormField(
              controller: _password2Controller,
              obscureText: _obscurePw2,
              enabled: !_isGoogleUser,
              decoration: InputDecoration(
                labelText: 'Passwort bestätigen',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePw2 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePw2 = !_obscurePw2),
                ),
              ),
              validator: (value) {
                if (_password1Controller.text.isNotEmpty && value != _password1Controller.text) {
                  return 'Passwörter stimmen nicht überein';
                }
                return null;
              },
            ),

            const SizedBox(height: 50),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 50),

            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Speichern'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _isLoading ? null : _saveProfile,
            ),

            const SizedBox(height: 50),
            Row(
              children: const [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Gefahrenbereich',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 35),

            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
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
                        'Konto unwiderruflich löschen',
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
                    'Dein Konto und alle Daten werden dauerhaft gelöscht. Dieser Vorgang kann nicht rückgängig gemacht werden.',
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('KONTO LÖSCHEN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _showDeleteAccountDialog,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

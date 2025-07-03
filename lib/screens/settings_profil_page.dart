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

            const SizedBox(height: 30),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 30),

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

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

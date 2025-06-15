import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsOverviewPage extends StatelessWidget {
  const SettingsOverviewPage({super.key});

  void _showPasswordAuthDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isObscured = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Authentifizierung'),
              content: TextField(
                autofocus: true,
                controller: controller,
                obscureText: isObscured,
                decoration: InputDecoration(
                  labelText: 'Aktuelles Passwort',
                  suffixIcon: IconButton(
                    icon: Icon(isObscured ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => isObscured = !isObscured),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Abbrechen'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Weiter'),
                  onPressed: () async {
                    final password = controller.text.trim();
                    if (password.isEmpty) return;

                    final success = true; // await verifyPassword(password);
                    if (success && context.mounted) {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/settingsProfil');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Passwort falsch')),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const SizedBox(height: 20),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profil'),
            subtitle: const Text('Name, Passwort ändern'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showPasswordAuthDialog(context);
            },
          ),

          const SizedBox(height: 20),

          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Theme'),
            subtitle: const Text('Hell, Dunkel oder System verwenden'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).pushNamed('/settingsTheme');
            },
          ),

          const SizedBox(height: 20),

          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Sprache'),
            subtitle: const Text('Aktuell: Deutsch'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Center(child: Text('Lern Deutsch')),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          const SizedBox(height: 30),
          const Divider(indent: 16, endIndent: 16),
          const SizedBox(height: 35),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Abmelden'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.red,
                backgroundColor: theme.colorScheme.surface,
                side: const BorderSide(color: Colors.red),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('loggedIn', false);

                if (!context.mounted) return;

                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              },
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

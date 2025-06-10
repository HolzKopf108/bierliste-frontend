import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsOverviewPage extends StatelessWidget {
  const SettingsOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // Profil
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profil'),
            subtitle: const Text('Name, Passwort ändern'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Wenn Profilseite existiert, hier Route hinzufügen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profil-Seite noch nicht vorhanden')),
              );
            },
          ),

          // Theme
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Theme'),
            subtitle: const Text('Hell, Dunkel oder System verwenden'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).pushNamed('/theme');
            },
          ),

          // Sprache (optional)
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Sprache'),
            subtitle: const Text('Aktuell: Deutsch'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sprachumschaltung noch nicht implementiert')),
              );
            },
          ),

          const Divider(height: 32),

          // Logout
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

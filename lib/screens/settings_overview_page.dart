import 'package:bierliste/providers/auth_provider.dart';
import 'package:bierliste/providers/user_provider.dart';
import 'package:bierliste/services/user_api_service.dart';
import 'package:bierliste/services/user_settings_api_service.dart';
import 'package:bierliste/utils/navigation_helper.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

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

                    final success = await UserSettingsApiService().verifyPassword(password);
                    if (success && context.mounted) {
                      safePop(context);
                      safePushNamed(context, '/settingsProfil');
                    } else {
                      if (!context.mounted) return;
                      safePop(context);
                      Toast.show(context, 'Passwort falsch');
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

  void _logout(BuildContext context) async {
    final userApiService = UserApiService();
    
    await userApiService.logout();

    if (!context.mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.logout();
  }

  void updateAutoSyncEnabled(BuildContext context, bool newAutoSync) async {
    final syncProvider = Provider.of<SyncProvider>(context, listen: false);
    
    final error = await syncProvider.setAutoSyncEnabled(newAutoSync);

    if(error != null) {
      if(!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Fehler'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncProvider = Provider.of<SyncProvider>(context);
    final isGoogleUser = context.read<UserProvider>().user?.googleUser ?? false;

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
              if (isGoogleUser) {
                safePushNamed(context, '/settingsProfil');
              } else {
                _showPasswordAuthDialog(context);
              }
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

          const SizedBox(height: 20),

          SwitchListTile(
            title: const Text('Auto-Sync'),
            subtitle: Text(syncProvider.isAutoSyncEnabled
                ? 'Online-Modus aktiviert'
                : 'Offline-Modus aktiviert'),
            value: syncProvider.isAutoSyncEnabled,
            onChanged: (value) {
              updateAutoSyncEnabled(context, value);              
            },
            secondary: const Icon(Icons.sync),
          ),

          const SizedBox(height: 35),
          const Divider(indent: 16, endIndent: 16),
          const SizedBox(height: 40),

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
              onPressed: () => _logout(context),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

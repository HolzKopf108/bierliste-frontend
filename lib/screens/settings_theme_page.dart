import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

class SettingsThemePage extends StatelessWidget {
  const SettingsThemePage({super.key});

  void updateTheme(BuildContext context, ThemeMode mode) async {
    final provider = Provider.of<ThemeProvider>(context, listen: false);
    provider.setTheme(mode);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ThemeProvider>(context);
    final currentMode = provider.themeMode;

    return Scaffold(
      appBar: AppBar(title: const Text('Theme ändern')),
      body: RadioGroup<ThemeMode>(
        groupValue: currentMode,
        onChanged: (mode) {
          if (mode != null) updateTheme(context, mode);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 30),
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
            ),
            const SizedBox(height: 30),
            RadioListTile<ThemeMode>(
              title: const Text('Hell'),
              value: ThemeMode.light,
            ),
            const SizedBox(height: 30),
            RadioListTile<ThemeMode>(
              title: const Text('Dunkel'),
              value: ThemeMode.dark,
            ),
            const SizedBox(height: 75),
          ],
        ),
      ),
    );
  }
}

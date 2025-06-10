import 'package:flutter/material.dart';

class GroupOverviewPage extends StatefulWidget {
  const GroupOverviewPage({super.key});

  @override
  State<GroupOverviewPage> createState() => _GroupOverviewPageState();
}

class _GroupOverviewPageState extends State<GroupOverviewPage> {
  // Beispiel-Daten
  final List<String> _groups = ['WG Küche', 'Bierfreunde', 'Kneipenrunde'];

  void _createNewGroup() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();

        return AlertDialog(
          title: const Text('Neue Gruppe erstellen'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Gruppenname'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  setState(() => _groups.add(name));
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Erstellen'),
            ),
          ],
        );
      },
    );
  }

  void _openGroup(String groupName) {
    Navigator.pushNamed(
      context,
      '/groupDetail',
      arguments: groupName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruppenübersicht'),
      ),
      body: _groups.isEmpty
          ? const Center(child: Text('Keine Gruppen vorhanden'))
          : ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                return ListTile(
                  leading: const Icon(Icons.group),
                  title: Text(group),
                  onTap: () => _openGroup(group),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewGroup,
        child: const Icon(Icons.add),
      ),
    );
  }
}

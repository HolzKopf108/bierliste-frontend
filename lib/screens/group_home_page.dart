import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/toast.dart';

class GroupHomePage extends StatefulWidget {
  final String groupName;

  const GroupHomePage({super.key, required this.groupName});

  @override
  State<GroupHomePage> createState() => _GroupHomePageState();
}

class _GroupHomePageState extends State<GroupHomePage> {
  int _strichCount = 0;
  double _pricePerStrich = 1.5;

  void _incrementStrich([int amount = 1]) {
    setState(() {
      _strichCount += amount;
    });
  }

  void _showStrichDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Anzahl',
                    labelStyle: TextStyle(color: Colors.grey[600]),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleStrichInput(controller),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _handleStrichInput(controller),
                  child: const Text('Hinzufügen'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleStrichInput(TextEditingController controller) {
    final text = controller.text.trim();
    final value = int.tryParse(text);
    if (value == null || value <= 0) {
      Toast.show(context, 'Bitte eine gültige Anzahl eingeben');
      return;
    }
    _incrementStrich(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final currency = (_strichCount * _pricePerStrich).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        leading: IconButton(
          icon: const Icon(Icons.group),
          onPressed: () => Navigator.pushNamed(
                            context,
                            '/groups',
                            arguments: widget.groupName,
                          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 75),
            ElevatedButton(
              onPressed: () => _incrementStrich(),
              onLongPress: _showStrichDialog,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 65),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Column(
                children: const [
                  Text(
                    'Strich machen',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Halten für mehrere',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 45),
            Center(
              child: Text(
                '$_strichCount ${_strichCount == 1 ? 'Strich' : 'Striche'}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 15),
            Center(
              child: Text(
                '$currency €',
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 65),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('Mitgliederübersicht'),
              subtitle: const Text('Alle Mitglieder & Striche sehen'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pushNamed(context, '/groupUsers', arguments: widget.groupName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Verlauf'),
              subtitle: const Text('Aktivitäten anzeigen'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).pushNamed(
                  '/groupActivity',
                  arguments: {
                    'groupId': "hallo",
                    'groupName': widget.groupName,
                    'currentUserId': "ich",
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.handyman),
              title: const Text('Gruppeneinstellungen'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pushNamed(context, '/groupSettings', arguments: 000000000);
              },
            ),
          ],
        ),
      ),
    );
  }
}

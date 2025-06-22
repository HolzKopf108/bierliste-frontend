import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animated_list_plus/animated_list_plus.dart';
import 'package:animated_list_plus/transitions.dart';

class GroupOverviewPage extends StatefulWidget {
  final String? previousGroup;

  const GroupOverviewPage({super.key, this.previousGroup});

  @override
  State<GroupOverviewPage> createState() => _GroupOverviewPageState();
}

class _GroupOverviewPageState extends State<GroupOverviewPage> {
  final List<String> _groups = ['WG Küche', 'Bierfreunde', 'Kneipenrunde'];
  String? _favoriteGroup;
  String? _previousGroup;
  late SharedPreferences _prefs;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _previousGroup = widget.previousGroup;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final fav = _prefs.getString('favoriteGroup');
    setState(() {
      _favoriteGroup = fav;
      _ensureFavoriteExists();
      _prefsLoaded = true;
    });
  }

  void _saveFavorite(String groupName) {
    _prefs.setString('favoriteGroup', groupName);
  }

  void _ensureFavoriteExists() {
    if (_groups.isNotEmpty && !_groups.contains(_favoriteGroup)) {
      _favoriteGroup = _groups.first;
      _saveFavorite(_favoriteGroup!);
    }
  }

  void _createNewGroup() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();

        return AlertDialog(
          title: const Text('Neue Gruppe erstellen'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Gruppenname',
              border: const OutlineInputBorder(),
            ),
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
                  setState(() {
                    _groups.add(name);
                    _ensureFavoriteExists();
                  });
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
    if (groupName.trim().toLowerCase() == _previousGroup?.trim().toLowerCase()) {
      safePop(context);
    } else {
      safePushNamed(context, '/groupDetail', arguments: groupName);
    }
  }

  void _setFavorite(String groupName) {
    setState(() {
      _favoriteGroup = groupName;
    });
    _saveFavorite(groupName);
  }

  List<String> _sortedGroups() {
    if (_groups.isEmpty) return [];

    final favorite = _favoriteGroup ?? _groups.first;

    final others = List<String>.from(_groups)
      ..remove(favorite)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [favorite, ...others];
  }

  @override
  Widget build(BuildContext context) {
    final sortedGroups = _sortedGroups();
    final favorite = _favoriteGroup ?? (_groups.isNotEmpty ? _groups.first : null);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruppenübersicht'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: !_prefsLoaded
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('Keine Gruppen vorhanden'))
              : ImplicitlyAnimatedList<String>(
                  padding: const EdgeInsets.all(16.0),
                  items: sortedGroups,
                  areItemsTheSame: (a, b) => a == b,
                  itemBuilder: (context, animation, group, index) {
                    final isFavorite = group == favorite;

                    return SizeFadeTransition(
                      animation: animation,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: const Icon(Icons.group),
                          title: Text(group),
                          trailing: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: IconButton(
                              key: ValueKey<bool>(isFavorite),
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                color: isFavorite ? primaryColor : Colors.grey,
                              ),
                              onPressed: () => _setFavorite(group),
                            ),
                          ),
                          onTap: () => _openGroup(group),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: SizedBox(
        height: 70,
        child: FloatingActionButton.extended(
          onPressed: _createNewGroup,
          icon: const Icon(Icons.add),
          label: const Text('Gruppe erstellen'),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
        ),
      ),
    );
  }
}

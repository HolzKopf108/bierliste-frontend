import 'package:bierliste/utils/navigation_helper.dart';
import 'package:bierliste/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animated_list_plus/animated_list_plus.dart';
import 'package:animated_list_plus/transitions.dart';

import '../models/group.dart';
import '../routes/app_routes.dart';
import '../services/group_api_service.dart';
import '../services/http_service.dart';

class GroupOverviewPage extends StatefulWidget {
  final int? previousGroupId;
  final GroupApiService? groupApiService;

  const GroupOverviewPage({
    super.key,
    this.previousGroupId,
    this.groupApiService,
  });

  @override
  State<GroupOverviewPage> createState() => _GroupOverviewPageState();
}

class _GroupOverviewPageState extends State<GroupOverviewPage> {
  late final GroupApiService _groupApiService;
  final List<Group> _groups = [];
  int? _favoriteGroupId;
  int? _previousGroupId;
  late SharedPreferences _prefs;
  bool _prefsLoaded = false;
  bool _isLoading = true;
  bool _isCreating = false;
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
    _groupApiService = widget.groupApiService ?? GroupApiService();
    _previousGroupId = widget.previousGroupId;
    _initialize();
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _favoriteGroupId = _prefs.getInt('favoriteGroupId');
    setState(() {
      _prefsLoaded = true;
    });
    await _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    try {
      final groups = await _groupApiService.listGroups();
      if (!mounted) return;

      setState(() {
        _groups
          ..clear()
          ..addAll(groups);
        _ensureFavoriteExists();
        _isLoading = false;
        _loadErrorMessage = null;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } on GroupApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _groups.clear();
        _isLoading = false;
        _loadErrorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groups.clear();
        _isLoading = false;
        _loadErrorMessage = 'Gruppen konnten nicht geladen werden';
      });
    }
  }

  void _saveFavorite(int groupId) {
    _prefs.setInt('favoriteGroupId', groupId);
  }

  void _ensureFavoriteExists() {
    if (_groups.isEmpty) {
      _favoriteGroupId = null;
      _prefs.remove('favoriteGroupId');
      return;
    }

    final favoriteExists = _groups.any((group) => group.id == _favoriteGroupId);
    if (!favoriteExists) {
      _favoriteGroupId = _groups.first.id;
      _saveFavorite(_favoriteGroupId!);
    }
  }

  Future<void> _createNewGroup() async {
    final groupName = await showDialog<String>(
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
                  Navigator.of(context).pop(name);
                }
              },
              child: const Text('Erstellen'),
            ),
          ],
        );
      },
    );

    if (groupName == null || groupName.isEmpty || !mounted) return;

    if (groupName.length < 3) {
      Toast.show(
        context,
        'Der Gruppenname muss mindestens 3 Zeichen lang sein',
        type: ToastType.warning,
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      await _groupApiService.createGroup(groupName);
      if (!mounted) return;

      await _loadGroups();
      if (!mounted) return;
      Toast.show(
        context,
        'Gruppe erfolgreich erstellt',
        type: ToastType.success,
      );
    } on UnauthorizedException {
      return;
    } on GroupApiException catch (e) {
      if (!mounted) return;
      Toast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      Toast.show(context, 'Gruppe konnte nicht erstellt werden');
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _openGroup(Group group) {
    if (group.id == _previousGroupId) {
      safePop(context);
    } else {
      safePushNamed(
        context,
        '/groupDetail',
        arguments: AppRoutes.groupArgs(group.id, groupName: group.name),
      );
    }
  }

  void _setFavorite(int groupId) {
    setState(() {
      _favoriteGroupId = groupId;
    });
    _saveFavorite(groupId);
  }

  List<Group> _sortedGroups() {
    if (_groups.isEmpty) return [];

    final favoriteId = _favoriteGroupId ?? _groups.first.id;
    final favorite = _groups.firstWhere((group) => group.id == favoriteId);

    final others = List<Group>.from(_groups)
      ..remove(favorite)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return [favorite, ...others];
  }

  @override
  Widget build(BuildContext context) {
    final sortedGroups = _sortedGroups();
    final favorite =
        _favoriteGroupId ?? (_groups.isNotEmpty ? _groups.first.id : null);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final canGoBack = Navigator.of(context).canPop() && _groups.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Gruppenübersicht'),
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: !_prefsLoaded || _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadErrorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48),
                    const SizedBox(height: 16),
                    Text(_loadErrorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadGroups,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut laden'),
                    ),
                  ],
                ),
              ),
            )
          : _groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group_off, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Keine Gruppen vorhanden',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Erstelle eine neue Gruppe oder öffne einen Einladungslink.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadGroups,
              child: ImplicitlyAnimatedList<Group>(
                padding: const EdgeInsets.all(16.0),
                items: sortedGroups,
                areItemsTheSame: (a, b) => a.id == b.id,
                itemBuilder: (context, animation, group, index) {
                  final isFavorite = group.id == favorite;

                  return SizeFadeTransition(
                    animation: animation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.group),
                        title: Text(group.name),
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
                            onPressed: () => _setFavorite(group.id),
                          ),
                        ),
                        onTap: () => _openGroup(group),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: SizedBox(
        height: 70,
        child: FloatingActionButton.extended(
          onPressed: _isCreating ? null : _createNewGroup,
          icon: _isCreating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_isCreating ? 'Erstelle...' : 'Gruppe erstellen'),
          extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
        ),
      ),
    );
  }
}

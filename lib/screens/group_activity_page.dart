import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group_activity.dart';
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/user_provider.dart';
import '../services/connectivity_service.dart';
import '../services/group_activity_api_service.dart';
import '../services/http_service.dart';
import '../services/offline_group_activity_service.dart';
import '../services/offline_group_users_service.dart';
import '../utils/group_activity_formatter.dart';

enum ActivityFilter { all, mine }

class GroupActivityPage extends StatefulWidget {
  final int groupId;

  const GroupActivityPage({super.key, required this.groupId});

  @override
  State<GroupActivityPage> createState() => _GroupActivityPageState();
}

class _GroupActivityPageState extends State<GroupActivityPage> {
  final GroupActivityApiService _groupActivityApiService =
      GroupActivityApiService();
  final ScrollController _scrollController = ScrollController();

  List<GroupActivity> _activities = [];
  ActivityFilter _filter = ActivityFilter.all;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _loadErrorMessage;
  String? _inlineErrorMessage;
  String? _loadMoreErrorMessage;
  String? _nextCursor;
  int? _currentUserId;
  SyncProvider? _syncProvider;
  bool _wasOnline = false;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_loadActivities());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final syncProvider = context.read<SyncProvider>();
    if (_syncProvider == syncProvider) {
      return;
    }

    _syncProvider?.removeListener(_handleSyncProviderChanged);
    _syncProvider = syncProvider;
    _wasOnline = syncProvider.isAppOnline;
    _wasSyncing = syncProvider.isSyncing;
    syncProvider.addListener(_handleSyncProviderChanged);
  }

  @override
  void dispose() {
    _syncProvider?.removeListener(_handleSyncProviderChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadActivities({bool showLoading = true}) async {
    final userEmail = context.read<AuthProvider>().userEmail;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _loadErrorMessage = null;
        _inlineErrorMessage = null;
        _loadMoreErrorMessage = null;
      });
    } else {
      setState(() {
        _loadErrorMessage = null;
        _inlineErrorMessage = null;
        _loadMoreErrorMessage = null;
      });
    }

    if (userEmail == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _activities = [];
        _nextCursor = null;
        _currentUserId = null;
        _isLoading = false;
        _loadErrorMessage = 'Verlauf konnte nicht geladen werden';
      });
      return;
    }

    final currentUserId = await _resolveCurrentUserId(userEmail);
    final cachedResponse = await OfflineGroupActivityService.getGroupActivities(
      userEmail,
      widget.groupId,
    );

    if (!mounted) {
      return;
    }

    if (cachedResponse != null) {
      setState(() {
        _activities = cachedResponse.items;
        _nextCursor = cachedResponse.nextCursor;
        _currentUserId = currentUserId;
        _isLoading = false;
        _loadErrorMessage = null;
      });
    } else {
      _currentUserId = currentUserId;
    }

    final isOnline = await ConnectivityService.isOnline();
    if (!mounted) {
      return;
    }

    if (!isOnline) {
      if (cachedResponse != null) {
        setState(() {
          _currentUserId = currentUserId;
          _isLoading = false;
          _inlineErrorMessage =
              'Keine Verbindung. Letzter Online-Stand wird angezeigt.';
        });
      } else {
        setState(() {
          _activities = [];
          _nextCursor = null;
          _currentUserId = currentUserId;
          _isLoading = false;
          _loadErrorMessage = 'Keine Verbindung';
        });
      }
      return;
    }

    try {
      final response = await OfflineGroupActivityService.refreshGroupActivities(
        userEmail,
        widget.groupId,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _activities = response.items;
        _nextCursor = response.nextCursor;
        _currentUserId = currentUserId;
        _isLoading = false;
        _loadErrorMessage = null;
        _inlineErrorMessage = null;
        _loadMoreErrorMessage = null;
      });
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
    } on GroupActivityApiException catch (e) {
      _applyLoadFailure(
        exception: e,
        cachedResponse: cachedResponse,
        currentUserId: currentUserId,
      );
    } on TimeoutException {
      _applyConnectivityLoadFailure(
        cachedResponse: cachedResponse,
        currentUserId: currentUserId,
      );
    } catch (_) {
      _applyConnectivityLoadFailure(
        cachedResponse: cachedResponse,
        currentUserId: currentUserId,
      );
    }
  }

  Future<void> _loadMore() async {
    final nextCursor = _nextCursor?.trim();
    if (_isLoading ||
        _isLoadingMore ||
        nextCursor == null ||
        nextCursor.isEmpty) {
      return;
    }

    if (!await ConnectivityService.isOnline()) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadMoreErrorMessage = 'Keine Verbindung';
      });
      return;
    }

    setState(() {
      _isLoadingMore = true;
      _loadMoreErrorMessage = null;
    });

    try {
      final response = await _groupActivityApiService.fetchGroupActivities(
        widget.groupId,
        cursor: nextCursor,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _activities = _appendUnique(_activities, response.items);
        _nextCursor = response.nextCursor;
        _isLoadingMore = false;
        _inlineErrorMessage = null;
      });
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingMore = false;
      });
    } on GroupActivityApiException catch (e) {
      if (!mounted) {
        return;
      }

      final blockingErrorMessage = _blockingLoadErrorMessage(e);
      if (blockingErrorMessage != null) {
        setState(() {
          _activities = [];
          _nextCursor = null;
          _isLoading = false;
          _isLoadingMore = false;
          _loadErrorMessage = blockingErrorMessage;
          _inlineErrorMessage = null;
          _loadMoreErrorMessage = null;
        });
        return;
      }

      setState(() {
        _isLoadingMore = false;
        _loadMoreErrorMessage = _friendlyLoadErrorMessage(e);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingMore = false;
        _loadMoreErrorMessage = 'Keine Verbindung';
      });
    }
  }

  Future<int?> _resolveCurrentUserId(String userEmail) async {
    final currentUsername = context.read<UserProvider>().user?.username.trim();
    if (currentUsername == null || currentUsername.isEmpty) {
      return null;
    }

    final members = await OfflineGroupUsersService.getGroupMembers(
      userEmail,
      widget.groupId,
    );
    if (members == null) {
      return null;
    }

    final normalizedCurrentUsername = currentUsername.toLowerCase();
    for (final member in members) {
      if (member.username.trim().toLowerCase() == normalizedCurrentUsername) {
        return member.userId;
      }
    }

    return null;
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.extentAfter < 240) {
      unawaited(_loadMore());
    }
  }

  void _handleSyncProviderChanged() {
    final syncProvider = _syncProvider;
    if (syncProvider == null) {
      return;
    }

    final isOnline = syncProvider.isAppOnline;
    final isSyncing = syncProvider.isSyncing;
    final shouldReload =
        (!_wasOnline && isOnline) || (_wasSyncing && !isSyncing);

    _wasOnline = isOnline;
    _wasSyncing = isSyncing;

    if (shouldReload && mounted && !_isLoading && !_isLoadingMore) {
      unawaited(_loadActivities(showLoading: false));
    }
  }

  void _applyLoadFailure({
    required GroupActivityApiException exception,
    required GroupActivitiesResponse? cachedResponse,
    required int? currentUserId,
  }) {
    if (!mounted) {
      return;
    }

    final blockingErrorMessage = _blockingLoadErrorMessage(exception);
    if (blockingErrorMessage != null) {
      setState(() {
        _activities = [];
        _nextCursor = null;
        _currentUserId = currentUserId;
        _isLoading = false;
        _loadErrorMessage = blockingErrorMessage;
        _inlineErrorMessage = null;
        _loadMoreErrorMessage = null;
      });
      return;
    }

    final friendlyMessage = _friendlyLoadErrorMessage(exception);
    if (cachedResponse != null) {
      setState(() {
        _currentUserId = currentUserId;
        _isLoading = false;
        _inlineErrorMessage = friendlyMessage;
      });
      return;
    }

    setState(() {
      _activities = [];
      _nextCursor = null;
      _currentUserId = currentUserId;
      _isLoading = false;
      _loadErrorMessage = friendlyMessage;
      _inlineErrorMessage = null;
      _loadMoreErrorMessage = null;
    });
  }

  void _applyConnectivityLoadFailure({
    required GroupActivitiesResponse? cachedResponse,
    required int? currentUserId,
  }) {
    if (!mounted) {
      return;
    }

    if (cachedResponse != null) {
      setState(() {
        _currentUserId = currentUserId;
        _isLoading = false;
        _inlineErrorMessage =
            'Keine Verbindung. Letzter Online-Stand wird angezeigt.';
      });
      return;
    }

    setState(() {
      _activities = [];
      _nextCursor = null;
      _currentUserId = currentUserId;
      _isLoading = false;
      _loadErrorMessage = 'Keine Verbindung';
    });
  }

  String? _blockingLoadErrorMessage(GroupActivityApiException exception) {
    switch (exception.statusCode) {
      case 403:
        return 'Kein Zugriff auf den Verlauf';
      case 404:
        return 'Gruppe nicht gefunden / kein Zugriff';
      default:
        return null;
    }
  }

  String _friendlyLoadErrorMessage(GroupActivityApiException exception) {
    if (_isConnectivityError(exception)) {
      return 'Keine Verbindung';
    }

    final message = exception.message.trim();
    if (message.isEmpty) {
      return 'Verlauf konnte nicht geladen werden';
    }

    return message;
  }

  bool _isConnectivityError(GroupActivityApiException exception) {
    final normalizedMessage = exception.message.trim().toLowerCase();
    return exception.statusCode == null &&
        (normalizedMessage.contains('netzwerk') ||
            normalizedMessage.contains('verbindung') ||
            normalizedMessage.contains('refresh'));
  }

  List<GroupActivity> _visibleActivities() {
    if (_filter == ActivityFilter.all) {
      return _activities;
    }

    final currentUsername = context.read<UserProvider>().user?.username.trim();
    return _activities.where((activity) {
      if (_currentUserId != null && activity.involvesUserId(_currentUserId!)) {
        return true;
      }

      if (currentUsername == null || currentUsername.isEmpty) {
        return false;
      }

      return activity.involvesUsername(currentUsername);
    }).toList();
  }

  List<GroupActivity> _appendUnique(
    List<GroupActivity> existingActivities,
    List<GroupActivity> newActivities,
  ) {
    final existingIds = existingActivities
        .map((activity) => activity.id)
        .toSet();
    final mergedActivities = List<GroupActivity>.from(existingActivities);

    for (final activity in newActivities) {
      if (existingIds.add(activity.id)) {
        mergedActivities.add(activity);
      }
    }

    return mergedActivities;
  }

  Widget _buildInlineMessageCard(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(
              onPressed: () => _loadActivities(showLoading: false),
              child: const Text('Erneut laden'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(GroupActivity activity) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activity.type == ActivityType.groupSettingsChanged)
              _buildSettingsChangedContent(activity, theme)
            else
              Text(GroupActivityFormatter.formatDescription(activity)),
            const SizedBox(height: 8),
            Text(
              GroupActivityFormatter.formatTimestamp(activity.timestamp),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsChangedContent(GroupActivity activity, ThemeData theme) {
    final details = GroupActivityFormatter.formatSettingsChangedDetails(
      activity,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(GroupActivityFormatter.formatSettingsChangedTitle(activity)),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < details.length; i++) ...[
                  _buildSettingsChangedItem(details[i], theme),
                  if (i < details.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsChangedItem(String detail, ThemeData theme) {
    final separatorIndex = detail.indexOf(': ');
    final title = separatorIndex >= 0
        ? detail.substring(0, separatorIndex).trim()
        : detail.trim();
    final value = separatorIndex >= 0
        ? detail.substring(separatorIndex + 2).trim()
        : null;
    final arrowIndex = value?.indexOf(' -> ') ?? -1;
    final oldValue = arrowIndex >= 0
        ? value!.substring(0, arrowIndex).trim()
        : null;
    final newValue = arrowIndex >= 0
        ? value!.substring(arrowIndex + 4).trim()
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '•',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (value != null && value.isNotEmpty) ...[
                const SizedBox(height: 2),
                if (oldValue != null &&
                    oldValue.isNotEmpty &&
                    newValue != null &&
                    newValue.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(oldValue, style: theme.textTheme.bodyMedium),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      Text(newValue, style: theme.textTheme.bodyMedium),
                    ],
                  )
                else
                  Text(value, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBlockingState({
    required IconData icon,
    required String message,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut laden'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(List<GroupActivity> visibleActivities) {
    if (visibleActivities.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final message = _filter == ActivityFilter.mine
        ? 'Im geladenen Verlauf gibt es keine Aktivitäten, die dich betreffen.'
        : 'Noch keine Aktivitäten vorhanden.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }

  Widget _buildFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadMoreErrorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadMoreErrorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loadMore,
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      );
    }

    if (_nextCursor == null || _nextCursor!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: TextButton(
          onPressed: _loadMore,
          child: const Text('Ältere Einträge laden'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleActivities = _visibleActivities();
    final hasFooter =
        _isLoadingMore ||
        _loadMoreErrorMessage != null ||
        (_nextCursor != null && _nextCursor!.trim().isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verlauf'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.person,
              color: _filter == ActivityFilter.mine
                  ? Colors.white
                  : Colors.white54,
            ),
            tooltip: 'Nur ich',
            onPressed: () {
              setState(() {
                _filter = ActivityFilter.mine;
              });
            },
          ),
          IconButton(
            icon: Icon(
              Icons.group,
              color: _filter == ActivityFilter.all
                  ? Colors.white
                  : Colors.white54,
            ),
            tooltip: 'Alle',
            onPressed: () {
              setState(() {
                _filter = ActivityFilter.all;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadErrorMessage != null
          ? _buildBlockingState(
              icon: _loadErrorMessage == 'Keine Verbindung'
                  ? Icons.cloud_off
                  : Icons.error_outline,
              message: _loadErrorMessage!,
              onPressed: _loadActivities,
            )
          : RefreshIndicator(
              onRefresh: () => _loadActivities(showLoading: false),
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  if (_inlineErrorMessage != null) ...[
                    _buildInlineMessageCard(_inlineErrorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (visibleActivities.isEmpty)
                    _buildEmptyState(visibleActivities)
                  else
                    for (final activity in visibleActivities) ...[
                      _buildActivityCard(activity),
                      const SizedBox(height: 12),
                    ],
                  if (hasFooter) _buildFooter(),
                ],
              ),
            ),
    );
  }
}

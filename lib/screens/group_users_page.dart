import 'package:flutter/material.dart';
import '../models/group_member.dart';
import '../services/group_api_service.dart';
import '../services/http_service.dart';

enum SortOption { alphabet, strichCount }

class GroupUsersPage extends StatefulWidget {
  final int groupId;
  final String? groupName;

  const GroupUsersPage({super.key, required this.groupId, this.groupName});

  @override
  State<GroupUsersPage> createState() => _GroupUsersPageState();
}

class _GroupUsersPageState extends State<GroupUsersPage> {
  final GroupApiService _groupApiService = GroupApiService();
  List<GroupMember> _members = [];
  SortOption _sortOption = SortOption.alphabet;
  bool _isLoading = true;
  String? _loadErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    try {
      final members = await _groupApiService.listMembers(widget.groupId);
      if (!mounted) return;

      setState(() {
        _members = members;
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
        _members = [];
        _isLoading = false;
        _loadErrorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _members = [];
        _isLoading = false;
        _loadErrorMessage = 'Mitglieder konnten nicht geladen werden';
      });
    }
  }

  List<GroupMember> _sortedMembers() {
    final sorted = List<GroupMember>.from(_members);

    if (_sortOption == SortOption.alphabet) {
      sorted.sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
      return sorted;
    }

    sorted.sort((a, b) {
      final countCompare = b.strichCount.compareTo(a.strichCount);
      if (countCompare != 0) {
        return countCompare;
      }

      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final sortedMembers = _sortedMembers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitgliederübersicht'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.sort_by_alpha,
              color: _sortOption == SortOption.alphabet
                  ? Colors.white
                  : Colors.white54,
            ),
            onPressed: () => setState(() => _sortOption = SortOption.alphabet),
          ),
          IconButton(
            icon: Icon(
              Icons.local_bar,
              color: _sortOption == SortOption.strichCount
                  ? Colors.white
                  : Colors.white54,
            ),
            onPressed: () => setState(
              () => _sortOption = SortOption.strichCount,
            ),
          ),
        ],
      ),
      body: _isLoading
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
                      onPressed: _loadMembers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut laden'),
                    ),
                  ],
                ),
              ),
            )
          : sortedMembers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Keine Mitglieder vorhanden'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loadMembers,
                    child: const Text('Erneut laden'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadMembers,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                itemCount: sortedMembers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final member = sortedMembers[index];
                  final strichLabel = member.strichCount == 1
                      ? '1 Strich'
                      : '${member.strichCount} Striche';

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 4),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.person),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.username,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strichLabel,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            member.strichCount.toString(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

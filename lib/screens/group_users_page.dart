import 'package:flutter/material.dart';
import '../models/group_member.dart';
import '../services/group_api_service.dart';
import '../services/http_service.dart';
import '../widgets/toast.dart';

enum SortOption { alphabet, role }

class GroupUsersPage extends StatefulWidget {
  final int groupId;
  final String groupName;

  const GroupUsersPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupUsersPage> createState() => _GroupUsersPageState();
}

class _GroupUsersPageState extends State<GroupUsersPage> {
  final GroupApiService _groupApiService = GroupApiService();
  List<GroupMember> _members = [];
  SortOption _sortOption = SortOption.alphabet;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final members = await _groupApiService.listMembers(widget.groupId);
      if (!mounted) return;

      setState(() {
        _members = members;
        _isLoading = false;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } on GroupApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      Toast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      Toast.show(context, 'Mitglieder konnten nicht geladen werden');
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
      if (a.role != b.role) {
        if (a.role == GroupMemberRole.admin) return -1;
        if (b.role == GroupMemberRole.admin) return 1;
      }
      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    return sorted;
  }

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    return '$day.$month.$year';
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
              Icons.verified_user,
              color: _sortOption == SortOption.role
                  ? Colors.white
                  : Colors.white54,
            ),
            onPressed: () => setState(() => _sortOption = SortOption.role),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                  final isAdmin = member.role == GroupMemberRole.admin;

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
                                'Mitglied seit ${_formatDate(member.joinedAt)}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? primaryColor
                                : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            member.role.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black,
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

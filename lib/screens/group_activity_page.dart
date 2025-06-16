import 'dart:convert';
import 'package:bierliste/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

enum ActivityFilter { all, mine }
enum ActivityType {
  strich,
  geld,
  roleAssigned,
  roleRemoved,
  priceChanged,
  joined,
  left,
}

class Activity {
  final String id;
  final ActivityType type;
  final String actorName;
  final String? targetName;
  final int? count;         // bei Strichen
  final double? amount;     // bei Geld
  final double? oldPrice;   // bei Preisänderung
  final double? newPrice;   // bei Preisänderung
  final DateTime timestamp;

  Activity({
    required this.id,
    required this.type,
    required this.actorName,
    this.targetName,
    this.count,
    this.amount,
    this.oldPrice,
    this.newPrice,
    required this.timestamp,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    // Passe die Felder an dein Backend-Format an!
    final typeStr = json['type'] as String;
    ActivityType type;
    switch (typeStr) {
      case 'STRICH':
        type = ActivityType.strich;
        break;
      case 'GELD':
        type = ActivityType.geld;
        break;
      case 'ROLE_ASSIGNED':
        type = ActivityType.roleAssigned;
        break;
      case 'ROLE_REMOVED':
        type = ActivityType.roleRemoved;
        break;
      case 'PRICE_CHANGED':
        type = ActivityType.priceChanged;
        break;
      case 'JOINED':
        type = ActivityType.joined;
        break;
      case 'LEFT':
        type = ActivityType.left;
        break;
      default:
        throw Exception('Unknown activity type: $typeStr');
    }

    return Activity(
      id: json['id'] as String,
      type: type,
      actorName: json['actor']['name'] as String,
      targetName: json['target'] != null ? json['target']['name'] as String : null,
      count: json['count'] != null ? json['count'] as int : null,
      amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
      oldPrice: json['oldPrice'] != null ? (json['oldPrice'] as num).toDouble() : null,
      newPrice: json['newPrice'] != null ? (json['newPrice'] as num).toDouble() : null,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class GroupActivityPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId; 

  const GroupActivityPage({
    Key? key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
  }) : super(key: key);

  @override
  _GroupActivityPageState createState() => _GroupActivityPageState();
}

class _GroupActivityPageState extends State<GroupActivityPage> {
  static const _limit = 10;

  List<Activity> _activities = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  ActivityFilter _filter = ActivityFilter.all;

  @override
  void initState() {
    super.initState();
    _fetchActivities();
  }

  Future<void> _fetchActivities({bool loadMore = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    if (!loadMore) {
      _offset = 0;
      _activities.clear();
      _hasMore = true;
    }

    final filterParam = _filter == ActivityFilter.mine
        ? '&actorId=${widget.currentUserId}'
        : '';

    final url = Uri.https(
      '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}',
      AppConfig.activities,
      {
        'offset': _offset.toString(),
        'limit' : _limit.toString(),
        if (_filter == ActivityFilter.mine)
          'actorId': widget.currentUserId,
      },
    );

    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        final fetched = data.map((e) => Activity.fromJson(e)).toList();
        setState(() {
          _activities.addAll(fetched);
          _hasMore = fetched.length == _limit;
          _offset += fetched.length;
        });
      } else {
        // Fehler-Handling nach Bedarf
        debugPrint('Error fetching activities: ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception fetching activities: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatTimestamp(DateTime ts) {
    return DateFormat('dd.MM.yyyy HH:mm').format(ts);
  }

  Widget _buildDescription(Activity act) {
    switch (act.type) {
      case ActivityType.strich:
        return Text(
          '${act.actorName} hat bei ${act.targetName} ${act.count} Striche gemacht',
        );
      case ActivityType.geld:
        return Text(
          '${act.actorName} hat bei ${act.targetName} € ${act.amount?.toStringAsFixed(2)} eingezahlt',
        );
      case ActivityType.roleAssigned:
        return Text(
          '${act.actorName} hat ${act.targetName} zum Bierlistenwart gemacht',
        );
      case ActivityType.roleRemoved:
        return Text(
          '${act.actorName} hat ${act.targetName} die Rolle Bierlistenwart entzogen',
        );
      case ActivityType.priceChanged:
        return Text(
          '${act.actorName} hat den Bierstrichpreis von '
          '€ ${act.oldPrice?.toStringAsFixed(2)} auf '
          '€ ${act.newPrice?.toStringAsFixed(2)} geändert',
        );
      case ActivityType.joined:
        return Text(
          '${act.targetName} ist der Gruppe beigetreten',
        );
      case ActivityType.left:
        return Text(
          '${act.targetName} hat die Gruppe verlassen',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text('Verlauf'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.person,
              color:
                  _filter == ActivityFilter.mine ? Colors.white : Colors.white54,
            ),
            tooltip: 'Nur ich',
            onPressed: () {
              setState(() => _filter = ActivityFilter.mine);
              _fetchActivities();
            },
          ),
          IconButton(
            icon: Icon(
              Icons.group,
              color:
                  _filter == ActivityFilter.all ? Colors.white : Colors.white54,
            ),
            tooltip: 'Alle',
            onPressed: () {
              setState(() => _filter = ActivityFilter.all);
              _fetchActivities();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchActivities(loadMore: false),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _activities.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            if (i < _activities.length) {
              final act = _activities[i];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDescription(act),
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(act.timestamp),
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              );
            } else {
              // Load more button
              return Center(
                child: _isLoading
                    ? CircularProgressIndicator()
                    : TextButton(
                        onPressed: () => _fetchActivities(loadMore: true),
                        child: const Text('Mehr anzeigen'),
                      ),
              );
            }
          },
        ),
      ),
    );
  }
}

enum ActivityType {
  strichIncremented('STRICH_INCREMENTED'),
  stricheDeducted('STRICHE_DEDUCTED'),
  moneyDeducted('MONEY_DEDUCTED'),
  userJoinedGroup('USER_JOINED_GROUP'),
  userLeftGroup('USER_LEFT_GROUP'),
  roleGrantedWart('ROLE_GRANTED_WART'),
  roleRevokedWart('ROLE_REVOKED_WART'),
  groupSettingsChanged('GROUP_SETTINGS_CHANGED'),
  userRemovedFromGroup('USER_REMOVED_FROM_GROUP'),
  inviteCreated('INVITE_CREATED'),
  inviteUsed('INVITE_USED'),
  unknown('UNKNOWN');

  final String jsonValue;

  const ActivityType(this.jsonValue);

  static ActivityType fromJsonValue(dynamic value) {
    final normalizedValue = value?.toString().trim().toUpperCase();
    switch (normalizedValue) {
      case 'STRICH_INCREMENTED':
        return ActivityType.strichIncremented;
      case 'STRICHE_DEDUCTED':
        return ActivityType.stricheDeducted;
      case 'MONEY_DEDUCTED':
        return ActivityType.moneyDeducted;
      case 'USER_JOINED_GROUP':
        return ActivityType.userJoinedGroup;
      case 'USER_LEFT_GROUP':
        return ActivityType.userLeftGroup;
      case 'ROLE_GRANTED_WART':
        return ActivityType.roleGrantedWart;
      case 'ROLE_REVOKED_WART':
        return ActivityType.roleRevokedWart;
      case 'GROUP_SETTINGS_CHANGED':
        return ActivityType.groupSettingsChanged;
      case 'USER_REMOVED_FROM_GROUP':
        return ActivityType.userRemovedFromGroup;
      case 'INVITE_CREATED':
        return ActivityType.inviteCreated;
      case 'INVITE_USED':
        return ActivityType.inviteUsed;
      default:
        return ActivityType.unknown;
    }
  }
}

class GroupActivity {
  final int id;
  final DateTime timestamp;
  final ActivityType type;
  final int? actorUserId;
  final String actorName;
  final int? targetUserId;
  final String? targetName;
  final Map<String, dynamic> meta;

  const GroupActivity({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.actorName,
    this.actorUserId,
    this.targetUserId,
    this.targetName,
    this.meta = const {},
  });

  factory GroupActivity.fromJson(Map<String, dynamic> json) {
    final actor = _readUser(json['actor']);
    final target = _readUser(json['target']);
    final meta = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('timestamp')
      ..remove('type')
      ..remove('actor')
      ..remove('target');

    if (json['type'] != null) {
      meta['rawType'] = json['type'].toString();
    }

    return GroupActivity(
      id: _readInt(json['id'], 'id'),
      timestamp: _readDateTime(json['timestamp'], 'timestamp'),
      type: ActivityType.fromJsonValue(json['type']),
      actorUserId: actor.userId,
      actorName: actor.name ?? 'Unbekannt',
      targetUserId: target.userId,
      targetName: target.name,
      meta: _normalizeMap(meta),
    );
  }

  factory GroupActivity.fromCacheJson(Map<String, dynamic> json) {
    final rawMeta = json['meta'];
    return GroupActivity(
      id: _readInt(json['id'], 'id'),
      timestamp: _readDateTime(json['timestamp'], 'timestamp'),
      type: ActivityType.fromJsonValue(json['type']),
      actorUserId: _readNullableInt(json['actorUserId']),
      actorName: _readString(json['actorName'], 'actorName'),
      targetUserId: _readNullableInt(json['targetUserId']),
      targetName: _readNullableString(json['targetName']),
      meta: rawMeta is Map ? _normalizeMap(rawMeta) : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'type': type.jsonValue,
      'actorUserId': actorUserId,
      'actorName': actorName,
      'targetUserId': targetUserId,
      'targetName': targetName,
      'meta': _normalizeMap(meta),
    };
  }

  bool involvesUserId(int userId) {
    return actorUserId == userId || targetUserId == userId;
  }

  bool involvesUsername(String username) {
    final normalizedUsername = username.trim().toLowerCase();
    if (normalizedUsername.isEmpty) {
      return false;
    }

    final normalizedActorName = actorName.trim().toLowerCase();
    final normalizedTargetName = targetName?.trim().toLowerCase();
    return normalizedActorName == normalizedUsername ||
        normalizedTargetName == normalizedUsername;
  }

  static int _readInt(dynamic value, String key) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException('Ungueltiges Zahlenfeld: $key');
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim());
    }

    return null;
  }

  static String _readString(dynamic value, String key) {
    if (value is! String) {
      throw FormatException('Ungueltiges Textfeld: $key');
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      throw FormatException('Leeres Textfeld: $key');
    }

    return trimmedValue;
  }

  static String? _readNullableString(dynamic value) {
    if (value is! String) {
      return null;
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    return trimmedValue;
  }

  static DateTime _readDateTime(dynamic value, String key) {
    if (value is! String) {
      throw FormatException('Ungueltiges Datumsfeld: $key');
    }

    return DateTime.parse(value);
  }

  static _ActivityUser _readUser(dynamic value) {
    if (value is! Map) {
      return const _ActivityUser();
    }

    final normalizedValue = _normalizeMap(value);
    return _ActivityUser(
      userId: _readNullableInt(normalizedValue['userId']),
      name: _readNullableString(normalizedValue['usernameSnapshot']),
    );
  }

  static Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> value) {
    final normalized = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key == null) {
        continue;
      }

      normalized[entry.key.toString()] = _normalizeValue(entry.value);
    }
    return normalized;
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return _normalizeMap(value);
    }

    if (value is List) {
      return value.map(_normalizeValue).toList();
    }

    return value;
  }
}

class GroupActivitiesResponse {
  final List<GroupActivity> items;
  final String? nextCursor;
  final int limit;

  const GroupActivitiesResponse({
    required this.items,
    required this.limit,
    this.nextCursor,
  });

  factory GroupActivitiesResponse.fromJson(
    Map<String, dynamic> json, {
    required int requestedLimit,
  }) {
    final rawItems = json['items'];
    if (rawItems != null && rawItems is! List) {
      throw const FormatException('Ungueltige Verlaufsliste');
    }

    final items = (rawItems as List? ?? []).map<GroupActivity>((entry) {
      if (entry is! Map) {
        throw const FormatException('Ungueltiger Verlaufseintrag');
      }

      return GroupActivity.fromJson(Map<String, dynamic>.from(entry));
    }).toList();

    return GroupActivitiesResponse(
      items: items,
      nextCursor: _readNullableCursor(json['nextCursor']),
      limit: requestedLimit,
    );
  }

  factory GroupActivitiesResponse.fromCacheJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Ungueltiger Verlaufscache');
    }

    return GroupActivitiesResponse(
      items: rawItems.map<GroupActivity>((entry) {
        if (entry is! Map) {
          throw const FormatException('Ungueltiger Verlaufseintrag');
        }

        return GroupActivity.fromCacheJson(Map<String, dynamic>.from(entry));
      }).toList(),
      nextCursor: _readNullableCursor(json['nextCursor']),
      limit: GroupActivity._readNullableInt(json['limit']) ?? rawItems.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(),
      'nextCursor': nextCursor,
      'limit': limit,
    };
  }

  static String? _readNullableCursor(dynamic value) {
    if (value is! String) {
      return null;
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    return trimmedValue;
  }
}

class _ActivityUser {
  final int? userId;
  final String? name;

  const _ActivityUser({this.userId, this.name});
}

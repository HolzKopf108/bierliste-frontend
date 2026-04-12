enum GroupMemberRole {
  member('MEMBER'),
  wart('ADMIN'),
  unknown('UNKNOWN');

  final String jsonValue;

  const GroupMemberRole(this.jsonValue);

  static GroupMemberRole fromJsonValue(dynamic value) {
    final normalizedValue = value?.toString().trim().toUpperCase();
    switch (normalizedValue) {
      case 'MEMBER':
        return GroupMemberRole.member;
      case 'ADMIN':
      case 'WART':
        return GroupMemberRole.wart;
      default:
        return GroupMemberRole.unknown;
    }
  }
}

class GroupMember {
  final int userId;
  final String username;
  final int strichCount;
  final GroupMemberRole role;
  final double? outstandingAmount;
  final bool canReceiveNotification;
  final bool hasPendingNotification;
  final DateTime? lastNotificationSentAt;
  final DateTime? lastNotificationConfirmedAt;

  const GroupMember({
    required this.userId,
    required this.username,
    required this.strichCount,
    required this.role,
    this.outstandingAmount,
    this.canReceiveNotification = false,
    this.hasPendingNotification = false,
    this.lastNotificationSentAt,
    this.lastNotificationConfirmedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: _readInt(json, 'userId'),
      username: _readString(json, 'username'),
      strichCount: _readInt(json, 'strichCount'),
      role: GroupMemberRole.fromJsonValue(json['role']),
      outstandingAmount: _readOptionalDouble(json['outstandingAmount']),
      canReceiveNotification: json['canReceiveNotification'] == true,
      hasPendingNotification: json['hasPendingNotification'] == true,
      lastNotificationSentAt: _readOptionalDateTime(
        json['lastNotificationSentAt'],
      ),
      lastNotificationConfirmedAt: _readOptionalDateTime(
        json['lastNotificationConfirmedAt'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'strichCount': strichCount,
      'role': role.jsonValue,
      if (outstandingAmount != null) 'outstandingAmount': outstandingAmount,
      'canReceiveNotification': canReceiveNotification,
      'hasPendingNotification': hasPendingNotification,
      if (lastNotificationSentAt != null)
        'lastNotificationSentAt': lastNotificationSentAt!
            .toUtc()
            .toIso8601String(),
      if (lastNotificationConfirmedAt != null)
        'lastNotificationConfirmedAt': lastNotificationConfirmedAt!
            .toUtc()
            .toIso8601String(),
    };
  }

  GroupMember copyWith({
    int? userId,
    String? username,
    int? strichCount,
    GroupMemberRole? role,
    double? outstandingAmount,
    bool? canReceiveNotification,
    bool? hasPendingNotification,
    DateTime? lastNotificationSentAt,
    DateTime? lastNotificationConfirmedAt,
  }) {
    return GroupMember(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      strichCount: strichCount ?? this.strichCount,
      role: role ?? this.role,
      outstandingAmount: outstandingAmount ?? this.outstandingAmount,
      canReceiveNotification:
          canReceiveNotification ?? this.canReceiveNotification,
      hasPendingNotification:
          hasPendingNotification ?? this.hasPendingNotification,
      lastNotificationSentAt:
          lastNotificationSentAt ?? this.lastNotificationSentAt,
      lastNotificationConfirmedAt:
          lastNotificationConfirmedAt ?? this.lastNotificationConfirmedAt,
    );
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      throw FormatException('Fehlendes Feld: $key');
    }

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

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('Ungueltiges Textfeld: $key');
    }

    if (value.trim().isEmpty) {
      throw FormatException('Leeres Textfeld: $key');
    }

    return value;
  }

  static double? _readOptionalDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
      if (parsed != null) {
        return parsed;
      }
    }

    throw const FormatException('Ungueltiges Zahlenfeld');
  }

  static DateTime? _readOptionalDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}

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

  const GroupMember({
    required this.userId,
    required this.username,
    required this.strichCount,
    required this.role,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: _readInt(json, 'userId'),
      username: _readString(json, 'username'),
      strichCount: _readInt(json, 'strichCount'),
      role: GroupMemberRole.fromJsonValue(json['role']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'strichCount': strichCount,
      'role': role.jsonValue,
    };
  }

  GroupMember copyWith({
    int? userId,
    String? username,
    int? strichCount,
    GroupMemberRole? role,
  }) {
    return GroupMember(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      strichCount: strichCount ?? this.strichCount,
      role: role ?? this.role,
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
}

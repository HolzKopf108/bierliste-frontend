enum GroupMemberRole { member, admin }

class GroupMember {
  final int userId;
  final String username;
  final DateTime? joinedAt;
  final GroupMemberRole role;
  final int strichCount;

  const GroupMember({
    required this.userId,
    required this.username,
    required this.joinedAt,
    required this.role,
    required this.strichCount,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: _toInt(json['userId']),
      username: (json['username'] ?? '').toString(),
      joinedAt: _toDateTime(json['joinedAt']),
      role: GroupMemberRoleX.fromApiValue(json['role']?.toString()),
      strichCount: _toInt(json['strichCount'], fallback: 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'joinedAt': joinedAt?.toUtc().toIso8601String(),
      'role': role.apiValue,
      'strichCount': strichCount,
    };
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    return DateTime.parse(raw);
  }
}

extension GroupMemberRoleX on GroupMemberRole {
  String get apiValue {
    switch (this) {
      case GroupMemberRole.member:
        return 'MEMBER';
      case GroupMemberRole.admin:
        return 'ADMIN';
    }
  }

  static GroupMemberRole fromApiValue(String? value) {
    switch (value) {
      case 'ADMIN':
        return GroupMemberRole.admin;
      case 'MEMBER':
      default:
        return GroupMemberRole.member;
    }
  }

  String get label {
    switch (this) {
      case GroupMemberRole.admin:
        return 'Bierlistenwart';
      case GroupMemberRole.member:
        return 'Mitglied';
    }
  }
}

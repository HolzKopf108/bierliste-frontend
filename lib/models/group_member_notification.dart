class GroupMemberNotification {
  final int id;
  final int groupId;
  final int actorUserId;
  final String actorUsername;
  final int targetUserId;
  final String message;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  const GroupMemberNotification({
    required this.id,
    required this.groupId,
    required this.actorUserId,
    required this.actorUsername,
    required this.targetUserId,
    required this.message,
    required this.createdAt,
    this.confirmedAt,
  });

  bool get isOpen => confirmedAt == null;

  factory GroupMemberNotification.fromJson(Map<String, dynamic> json) {
    return GroupMemberNotification(
      id: _toInt(json['id']),
      groupId: _toInt(json['groupId']),
      actorUserId: _toInt(json['actorUserId']),
      actorUsername: (json['actorUsername'] ?? '').toString(),
      targetUserId: _toInt(json['targetUserId']),
      message: (json['message'] ?? '').toString(),
      createdAt: _toDateTime(json['createdAt']),
      confirmedAt: _toOptionalDateTime(json['confirmedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'actorUserId': actorUserId,
      'actorUsername': actorUsername,
      'targetUserId': targetUserId,
      'message': message,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (confirmedAt != null)
        'confirmedAt': confirmedAt!.toUtc().toIso8601String(),
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.parse(value.toString());
  }

  static DateTime _toDateTime(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw const FormatException('Ungueltiges Datumsfeld');
    }
    return parsed;
  }

  static DateTime? _toOptionalDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}

class ConfirmedCounterIncrement {
  final String localOperationId;
  final int groupId;
  final int amount;
  final int incrementRequestId;
  final DateTime undoExpiresAt;
  final int? targetUserId;
  final String? targetUsername;
  final bool affectsCurrentUser;

  const ConfirmedCounterIncrement({
    required this.localOperationId,
    required this.groupId,
    required this.amount,
    required this.incrementRequestId,
    required this.undoExpiresAt,
    this.targetUserId,
    this.targetUsername,
    this.affectsCurrentUser = false,
  });

  factory ConfirmedCounterIncrement.fromJson(Map<String, dynamic> json) {
    return ConfirmedCounterIncrement(
      localOperationId: (json['localOperationId'] ?? '').toString(),
      groupId: _toInt(json['groupId']),
      amount: _toInt(json['amount']),
      incrementRequestId: _toInt(json['incrementRequestId']),
      undoExpiresAt: _toDateTime(json['undoExpiresAt']),
      targetUserId: _toNullableInt(json['targetUserId']),
      targetUsername: _toNullableString(json['targetUsername']),
      affectsCurrentUser: json['affectsCurrentUser'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'localOperationId': localOperationId,
      'groupId': groupId,
      'amount': amount,
      'incrementRequestId': incrementRequestId,
      'undoExpiresAt': undoExpiresAt.toUtc().toIso8601String(),
      'targetUserId': targetUserId,
      'targetUsername': targetUsername,
      'affectsCurrentUser': affectsCurrentUser,
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

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static String? _toNullableString(dynamic value) {
    if (value is! String) {
      return null;
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    return trimmedValue;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.parse(value.toString()).toUtc();
  }
}

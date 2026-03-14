class PendingCounterOperation {
  static const String incrementOwnCounter = 'incrementOwnCounter';

  final String id;
  final String userEmail;
  final int groupId;
  final int amount;
  final int? targetUserId;
  final String operationType;
  final DateTime createdAt;

  const PendingCounterOperation({
    required this.id,
    required this.userEmail,
    required this.groupId,
    required this.amount,
    required this.operationType,
    required this.createdAt,
    this.targetUserId,
  });

  bool get isSyncableOwnCounterIncrement =>
      operationType == incrementOwnCounter &&
      targetUserId == null &&
      amount > 0;

  factory PendingCounterOperation.fromJson(Map<String, dynamic> json) {
    return PendingCounterOperation(
      id: (json['id'] ?? '').toString(),
      userEmail: (json['userEmail'] ?? '').toString(),
      groupId: _toInt(json['groupId']),
      amount: _toInt(json['amount']),
      targetUserId: json['targetUserId'] != null
          ? _toInt(json['targetUserId'])
          : null,
      operationType: (json['operationType'] ?? incrementOwnCounter).toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userEmail': userEmail,
      'groupId': groupId,
      'amount': amount,
      if (targetUserId != null) 'targetUserId': targetUserId,
      'operationType': operationType,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
}

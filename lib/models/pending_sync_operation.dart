class PendingSyncOperation {
  static const String domainCounter = 'counter';
  static const String domainGroupUsers = 'groupUsers';
  static const String domainGroupSettings = 'groupSettings';

  static const String incrementOwnCounter = 'incrementOwnCounter';
  static const String incrementGroupMemberCounter =
      'incrementGroupMemberCounter';
  static const String undoOwnCounterIncrement = 'undoOwnCounterIncrement';
  static const String undoGroupMemberCounterIncrement =
      'undoGroupMemberCounterIncrement';
  static const String promoteGroupMember = 'promoteGroupMember';
  static const String demoteGroupMember = 'demoteGroupMember';
  static const String settleGroupMemberMoney = 'settleGroupMemberMoney';
  static const String settleGroupMemberStriche = 'settleGroupMemberStriche';
  static const String updateGroupSettings = 'updateGroupSettings';

  final String id;
  final String userEmail;
  final String domain;
  final String operationType;
  final int groupId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextAttemptAt;

  const PendingSyncOperation({
    required this.id,
    required this.userEmail,
    required this.domain,
    required this.operationType,
    required this.groupId,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.nextAttemptAt,
  });

  bool get isReadyForSync {
    final nextAttemptAt = this.nextAttemptAt;
    if (nextAttemptAt == null) {
      return true;
    }

    return !nextAttemptAt.isAfter(DateTime.now().toUtc());
  }

  PendingSyncOperation copyWith({
    String? id,
    String? userEmail,
    String? domain,
    String? operationType,
    int? groupId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) {
    return PendingSyncOperation(
      id: id ?? this.id,
      userEmail: userEmail ?? this.userEmail,
      domain: domain ?? this.domain,
      operationType: operationType ?? this.operationType,
      groupId: groupId ?? this.groupId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
    );
  }

  factory PendingSyncOperation.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];

    return PendingSyncOperation(
      id: (json['id'] ?? '').toString(),
      userEmail: (json['userEmail'] ?? '').toString(),
      domain: (json['domain'] ?? '').toString(),
      operationType: (json['operationType'] ?? '').toString(),
      groupId: _toInt(json['groupId']),
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : <String, dynamic>{},
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      retryCount: _toInt(json['retryCount'] ?? 0),
      nextAttemptAt: json['nextAttemptAt'] != null
          ? DateTime.tryParse(json['nextAttemptAt'].toString())?.toUtc()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userEmail': userEmail,
      'domain': domain,
      'operationType': operationType,
      'groupId': groupId,
      'payload': payload,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'retryCount': retryCount,
      if (nextAttemptAt != null)
        'nextAttemptAt': nextAttemptAt!.toUtc().toIso8601String(),
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }
}

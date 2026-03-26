class CounterIncrementResult {
  final int count;
  final int incrementRequestId;
  final DateTime undoExpiresAt;

  const CounterIncrementResult({
    required this.count,
    required this.incrementRequestId,
    required this.undoExpiresAt,
  });

  factory CounterIncrementResult.fromJson(Map<String, dynamic> json) {
    return CounterIncrementResult(
      count: _toInt(json['count']),
      incrementRequestId: _toInt(json['incrementRequestId']),
      undoExpiresAt: _toDateTime(json['undoExpiresAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'incrementRequestId': incrementRequestId,
      'undoExpiresAt': undoExpiresAt.toUtc().toIso8601String(),
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
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.parse(value.toString()).toUtc();
  }
}

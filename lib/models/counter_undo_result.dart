class CounterUndoResult {
  final int count;
  final int incrementRequestId;
  final DateTime undoneAt;

  const CounterUndoResult({
    required this.count,
    required this.incrementRequestId,
    required this.undoneAt,
  });

  factory CounterUndoResult.fromJson(Map<String, dynamic> json) {
    return CounterUndoResult(
      count: _toInt(json['count']),
      incrementRequestId: _toInt(json['incrementRequestId']),
      undoneAt: _toDateTime(json['undoneAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'incrementRequestId': incrementRequestId,
      'undoneAt': undoneAt.toUtc().toIso8601String(),
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

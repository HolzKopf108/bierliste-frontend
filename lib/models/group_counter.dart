class GroupCounter {
  final int count;

  const GroupCounter({required this.count});

  factory GroupCounter.fromJson(Map<String, dynamic> json) {
    return GroupCounter(count: _toInt(json['count']));
  }

  Map<String, dynamic> toJson() {
    return {'count': count};
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
}

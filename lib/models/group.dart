class Group {
  final int id;
  final String name;
  final DateTime? createdAt;
  final int? createdByUserId;

  const Group({
    required this.id,
    required this.name,
    this.createdAt,
    this.createdByUserId,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: _toInt(json['id']),
      name: (json['name'] ?? '').toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      createdByUserId: json['createdByUserId'] != null
          ? _toInt(json['createdByUserId'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      if (createdByUserId != null) 'createdByUserId': createdByUserId,
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
}

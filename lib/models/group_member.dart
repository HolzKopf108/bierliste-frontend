class GroupMember {
  final int userId;
  final String username;
  final int strichCount;

  const GroupMember({
    required this.userId,
    required this.username,
    required this.strichCount,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: _readInt(json, 'userId'),
      username: _readString(json, 'username'),
      strichCount: _readInt(json, 'strichCount'),
    );
  }

  Map<String, dynamic> toJson() {
    return {'userId': userId, 'username': username, 'strichCount': strichCount};
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

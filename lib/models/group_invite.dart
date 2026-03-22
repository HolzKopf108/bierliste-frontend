class GroupInvite {
  final int? inviteId;
  final String token;
  final String joinUrl;
  final DateTime? expiresAt;

  const GroupInvite({
    this.inviteId,
    required this.token,
    required this.joinUrl,
    this.expiresAt,
  });

  factory GroupInvite.fromJson(Map<String, dynamic> json) {
    final token = (json['token'] ?? '').toString().trim();
    final joinUrl = (json['joinUrl'] ?? '').toString().trim();

    if (token.isEmpty) {
      throw const FormatException('Fehlender Invite-Token');
    }
    if (joinUrl.isEmpty) {
      throw const FormatException('Fehlende Join-URL');
    }

    return GroupInvite(
      inviteId: json['inviteId'] != null ? _toInt(json['inviteId']) : null,
      token: token,
      joinUrl: joinUrl,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
}

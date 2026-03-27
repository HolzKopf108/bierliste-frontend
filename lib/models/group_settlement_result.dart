import 'group_member.dart';

class GroupSettlementResult {
  final GroupMember member;

  const GroupSettlementResult({required this.member});

  factory GroupSettlementResult.fromJson(Map<String, dynamic> json) {
    if (!_looksLikeGroupMember(json)) {
      throw const FormatException('Ungueltige Settlement-Antwort');
    }

    return GroupSettlementResult(member: GroupMember.fromJson(json));
  }

  int get resolvedStrichCount => member.strichCount;

  static bool _looksLikeGroupMember(Map<String, dynamic> json) {
    return json.containsKey('userId') &&
        json.containsKey('username') &&
        json.containsKey('role') &&
        json.containsKey('strichCount');
  }
}

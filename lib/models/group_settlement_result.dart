import 'group_member.dart';

class GroupSettlementResult {
  final GroupMember? member;
  final int? newStrichCount;

  const GroupSettlementResult({this.member, this.newStrichCount});

  factory GroupSettlementResult.fromJson(Map<String, dynamic> json) {
    if (_looksLikeGroupMember(json)) {
      final parsedMember = GroupMember.fromJson(json);
      return GroupSettlementResult(
        member: parsedMember.copyWith(
          strichCount: _normalizeCount(parsedMember.strichCount),
        ),
      );
    }

    final parsedCount = _readOptionalInt(json['newStrichCount']);
    if (parsedCount != null) {
      return GroupSettlementResult(
        newStrichCount: _normalizeCount(parsedCount),
      );
    }

    throw const FormatException('Ungueltige Settlement-Antwort');
  }

  int? get resolvedStrichCount => member?.strichCount ?? newStrichCount;

  bool get hasMember => member != null;

  static bool _looksLikeGroupMember(Map<String, dynamic> json) {
    return json.containsKey('userId') &&
        json.containsKey('username') &&
        json.containsKey('role') &&
        json.containsKey('strichCount');
  }

  static int? _readOptionalInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString().trim());
  }

  static int _normalizeCount(int value) {
    return value < 0 ? 0 : value;
  }
}

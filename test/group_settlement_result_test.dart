import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/models/group_settlement_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'settlement result keeps negative strichCount from group member dto',
    () {
      final result = GroupSettlementResult.fromJson({
        'userId': 42,
        'username': 'Mia',
        'role': GroupMemberRole.member.jsonValue,
        'strichCount': -3,
      });

      expect(result.member.strichCount, -3);
      expect(result.resolvedStrichCount, -3);
    },
  );
}

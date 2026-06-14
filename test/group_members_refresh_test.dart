import 'dart:io';

import 'package:bierliste/models/group_member.dart';
import 'package:bierliste/services/group_api_service.dart';
import 'package:bierliste/services/offline_group_users_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? tempDir;

  Future<void> resetTestState() async {
    GroupApiService.testFetchGroupMembers = null;
    await Hive.close();
  }

  setUp(() async {
    await resetTestState();
    tempDir = await Directory.systemTemp.createTemp(
      'bierliste_group_members_refresh_',
    );
    Hive.init(tempDir!.path);
  });

  tearDown(() async {
    await resetTestState();
    final directory = tempDir;
    if (directory != null && directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    tempDir = null;
  });

  test(
    'refresh replaces stale former members with active backend members',
    () async {
      await OfflineGroupUsersService.saveGroupMembers('max@example.com', 5, [
        const GroupMember(
          userId: 1,
          username: 'Max',
          strichCount: 0,
          role: GroupMemberRole.wart,
        ),
        const GroupMember(
          userId: 2,
          username: 'Ben',
          strichCount: 3,
          role: GroupMemberRole.member,
        ),
      ]);

      GroupApiService.testFetchGroupMembers = (_) async {
        return const [
          GroupMember(
            userId: 1,
            username: 'Max',
            strichCount: 0,
            role: GroupMemberRole.wart,
          ),
        ];
      };

      final refreshedMembers =
          await OfflineGroupUsersService.refreshGroupMembers(
            'max@example.com',
            5,
          );
      final cachedMembers = await OfflineGroupUsersService.getGroupMembers(
        'max@example.com',
        5,
      );

      expect(refreshedMembers, hasLength(1));
      expect(refreshedMembers.single.username, 'Max');
      expect(refreshedMembers.single.userId, 1);

      expect(cachedMembers, isNotNull);
      expect(cachedMembers!, hasLength(1));
      expect(cachedMembers.single.username, 'Max');
      expect(cachedMembers.single.userId, 1);
    },
  );
}

import 'package:bierliste/services/offline_group_settings_service.dart';
import 'package:bierliste/services/offline_group_users_service.dart';
import 'package:bierliste/services/offline_strich_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';

class PendingSyncService {
  static Future<bool> hasPendingOperations(String userEmail) {
    return PendingSyncQueueService.hasPendingOperations(userEmail);
  }

  static Future<bool> syncPendingOperations(String userEmail) async {
    final results = await Future.wait<bool>([
      OfflineStrichService.syncPendingOperations(userEmail),
      OfflineGroupSettingsService.syncPendingOperations(userEmail),
      OfflineGroupUsersService.syncPendingOperations(userEmail),
    ]);

    return results.every((result) => result);
  }
}

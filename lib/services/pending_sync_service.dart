import 'package:bierliste/services/offline_group_settings_service.dart';
import 'package:bierliste/services/offline_group_users_service.dart';
import 'package:bierliste/services/offline_strich_service.dart';
import 'package:bierliste/services/pending_sync_queue_service.dart';
import 'package:bierliste/services/sync_debug_service.dart';

class PendingSyncService {
  static Future<bool> hasPendingOperations(String userEmail) {
    return PendingSyncQueueService.hasPendingOperations(userEmail);
  }

  static Future<bool> hasReadyOperations(String userEmail) async {
    final operations = await PendingSyncQueueService.getOperations(userEmail);
    return operations.any((operation) => operation.isReadyForSync);
  }

  static Future<bool> syncPendingOperations(String userEmail) async {
    final operationsBefore = await PendingSyncQueueService.getOperations(
      userEmail,
    );
    SyncDebugService.log(
      'PendingSyncService',
      'sync started',
      details: {
        'userEmail': userEmail,
        'operations': SyncDebugService.summarizeOperations(operationsBefore),
      },
    );

    final results = await Future.wait<bool>([
      OfflineStrichService.syncPendingOperations(userEmail),
      OfflineGroupSettingsService.syncPendingOperations(userEmail),
      OfflineGroupUsersService.syncPendingOperations(userEmail),
    ]);

    final success = results.every((result) => result);
    final operationsAfter = await PendingSyncQueueService.getOperations(
      userEmail,
    );
    SyncDebugService.log(
      'PendingSyncService',
      'sync finished',
      details: {
        'userEmail': userEmail,
        'counter': results[0],
        'groupSettings': results[1],
        'groupUsers': results[2],
        'success': success,
        'remainingOperations': SyncDebugService.summarizeOperations(
          operationsAfter,
        ),
      },
    );

    return success;
  }
}

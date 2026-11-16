import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

class SyncStatusIndicator extends StatelessWidget {
  final int? groupId;
  const SyncStatusIndicator({super.key, this.groupId});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final pending = groupId == null ? sync.hasPendingSync : sync.hasPendingForGroup(groupId!);
    final failed = groupId == null ? sync.problems.isNotEmpty : sync.hasProblemsForGroup(groupId!);
    if (!pending && !failed) return const SizedBox.shrink();
    final message = failed ? 'Synchronisierung fehlgeschlagen' : sync.isSyncing
        ? 'Wird synchronisiert' : 'Nicht synchronisiert';
    return IconButton(
      tooltip: message,
      onPressed: () => unawaited(sync.requestSync()),
      icon: Icon(failed ? Icons.sync_problem : sync.isSyncing ? Icons.sync : Icons.cloud_upload_outlined,
          color: failed ? Theme.of(context).colorScheme.error : null),
    );
  }
}

import 'dart:collection';

import 'package:bierliste/models/pending_sync_operation.dart';
import 'package:flutter/foundation.dart';

class SyncDebugService {
  static const int _maxEntries = 400;
  static bool enabled = kDebugMode;
  static final ListQueue<String> _entries = ListQueue<String>();

  static void log(
    String scope,
    String message, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!enabled) {
      return;
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final normalizedDetails = details.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final line = normalizedDetails.isEmpty
        ? '[SYNC][$scope] $timestamp $message'
        : '[SYNC][$scope] $timestamp $message $normalizedDetails';

    debugPrint(line);
    _entries.add(line);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
  }

  static void clear() {
    _entries.clear();
  }

  static List<String> entries() {
    return List<String>.unmodifiable(_entries);
  }

  static String summarizeOperations(List<PendingSyncOperation> operations) {
    if (operations.isEmpty) {
      return '[]';
    }

    return operations
        .map((operation) {
          final nextAttemptAt =
              operation.nextAttemptAt?.toIso8601String() ?? '-';
          return '${operation.operationType}'
              '(id=${operation.id},group=${operation.groupId},retry=${operation.retryCount},next=$nextAttemptAt)';
        })
        .join(', ');
  }
}

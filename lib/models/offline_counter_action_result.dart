class OfflineCounterActionResult {
  final int count;
  final bool hasPendingSync;
  final String? errorMessage;

  const OfflineCounterActionResult({
    required this.count,
    required this.hasPendingSync,
    this.errorMessage,
  });
}

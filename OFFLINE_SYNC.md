# Offline synchronization

The existing per-user Hive queue is shared by counters, members and settings.
Own increments use POST /api/v1/sync/events in request order, in batches of at most 20.
Each action keeps the same persisted UUID through retries and application restarts.
Applied/duplicate responses are acknowledged locally; transport failures keep the queue.
Retries use 15, 30, 60, 120, 240, then 480 seconds (capped), without a retry-count cutoff.
401 uses the existing token refresh/session handling. Whole-request failures never discard actions.
An incomplete or malformed response is retried using the same event IDs.
Permanent event failures are retained as terminal problems and are never retried automatically.
Other operation types retain their existing endpoints until the backend supports their event types.

Do not replay queued events older than the backend's deduplication retention (default 90 days)
without reviewing their state. A duplicate response contains the original result, not necessarily
the current counter; reconciliation must reload the current server counter.

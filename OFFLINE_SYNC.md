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
the current counter; duplicate groups reload it before acknowledgement. All successful
events for a group in a batch are acknowledged atomically with that group's baseline.
Pending optimistic deltas are calculated from the same Hive snapshot. GET responses that
predate local mutations or overlap an uncertain upload cannot replace this baseline.
An uncertain/retrying event blocks later actions in its group, not in other groups.

## Automatic triggers and errors

Sync runs on startup, resume and connectivity changes. A one-minute foreground timer
checks pending work; no server ping is sent when the queue is empty. Backgrounded apps
pause the timer and resume immediately on return. This is best effort, not an OS-level
background task that continues after the app is terminated.

Event failures 400/403/404/409 or resolution=drop stop retrying and roll back the optimistic
delta. The retained terminal record appears under Sync-Probleme and can be dismissed.
429, 5xx and transport errors keep the original event ID and schedule a retry. Auth failures
keep the queue for the original account; events must not be uploaded under another account.

## Verification

Run `flutter test` locally. CI uses Flutter 3.50.0 and non-secret configurations from
`.github/fixtures`; those placeholders must never be used to build a production app.
Actions are pinned to the reviewed release commits of
[checkout 7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) and
[flutter-action 2.23.0](https://github.com/subosito/flutter-action/releases/tag/v2.23.0),
with read-only repository permissions and no persisted checkout credentials.
The tests cover durable UUID migration, account/group separation, 20-event batches,
lost responses and duplicates, partial failures, backoff, concurrency, reconciliation,
automatic triggers and reactive status/problem indicators. Backend DB deduplication
is covered separately by the backend integration tests, not by these client-side fakes.

Manual acceptance test with a running backend:

1. Log in, open a group and note its server counter.
2. Disable networking and book several own increments. The count increases immediately;
   the header and group row show Nicht synchronisiert.
3. Fully close and reopen the app offline. The count and pending status must remain.
4. Restore networking or resume the app. The indicator clears after sync; refresh and
   reopen the group to confirm the server count. A second sync must not increment again.
5. Repeat while another session increments your counter. Reconciliation must include
   both sessions' accepted actions without adding the local queue twice.
6. Queue an action offline, remove membership in another session, then reconnect.
   The action must not be retried indefinitely; inspect and dismiss Sync-Probleme.

Implemented frontend children of backend epic #12: #73, #74, #75, #76, #77, #78,
#79, #80 and #81 in the frontend repository. New backend event types are not introduced.

import 'dart:async';

/// Outcome of a Firestore write when offline persistence is in play.
enum WriteSyncResult {
  /// The write was acknowledged by the server.
  synced,

  /// The server didn't acknowledge in time (almost always because the device
  /// is offline). Firestore has applied the change to its local cache and will
  /// upload it automatically once connectivity returns.
  queuedOffline,
}

/// Await a Firestore write, but don't hang forever when offline.
///
/// Firestore intentionally leaves write futures (`set`/`update`/`add`/
/// `WriteBatch.commit`) pending until the server acknowledges them. Offline
/// that never happens, so a naive `await` would block the UI indefinitely even
/// though the change is already visible in the local cache.
///
/// This races the write against [timeout]:
///   * completes normally in time  -> [WriteSyncResult.synced]
///   * still pending after timeout  -> [WriteSyncResult.queuedOffline] (the
///     write keeps running in the background and will sync later; any eventual
///     error is swallowed so it doesn't surface as an unhandled exception)
///   * fails before the timeout     -> the error is rethrown (e.g. a rules
///     rejection while online), so callers can show a real error.
Future<WriteSyncResult> commitWithOfflineFallback(
  Future<Object?> write, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    await write.timeout(timeout);
    return WriteSyncResult.synced;
  } on TimeoutException {
    // Likely offline: the mutation is queued in Firestore's local cache and
    // will replay on reconnect. Keep listening so a later failure (e.g. a
    // rules rollback on sync) doesn't become an unhandled exception.
    unawaited(write.catchError((_) => null));
    return WriteSyncResult.queuedOffline;
  }
}

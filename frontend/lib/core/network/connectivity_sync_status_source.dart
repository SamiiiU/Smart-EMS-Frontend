import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../shell/sync_status.dart';

/// Real implementation of T5's [SyncStatusSource] seam, backed by
/// `connectivity_plus`.
///
/// **Pending-count is stubbed at 0.** There is no offline write-queue yet —
/// that is T8's job. Wiring a fake non-zero count here would be inventing
/// data; 0 is honestly what there is to report today. When T8 lands its
/// queue, this class gets a real counter injected and the seam this class
/// exists for is exactly the one-line change T5 promised.
class ConnectivitySyncStatusSource implements SyncStatusSource {
  ConnectivitySyncStatusSource({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    // `connectivity_plus` has no synchronous initial-state API, so `current`
    // reports `synced` for the first frame until `checkConnectivity()`
    // resolves (typically sub-millisecond, but not zero) — a small deviation
    // from T5's "must be synchronous, never a network round trip" doc
    // comment, which assumed a platform API with a sync accessor. Logged in
    // HANDOFF.md rather than silently accepted.
    _current = const SyncStatus.synced();
    _sub = _connectivity.onConnectivityChanged.listen(_onChange);
    _connectivity.checkConnectivity().then(_onChange);
  }

  final Connectivity _connectivity;
  late StreamSubscription<List<ConnectivityResult>> _sub;
  late SyncStatus _current;
  final _controller = StreamController<SyncStatus>.broadcast();

  void _onChange(List<ConnectivityResult> results) {
    final next = isOffline(results)
        ? const SyncStatus.offline()
        : const SyncStatus.synced();
    if (next != _current) {
      _current = next;
      _controller.add(next);
    }
  }

  @override
  SyncStatus get current => _current;

  @override
  Stream<SyncStatus> get statusStream => _controller.stream;

  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

/// Pulled out as a pure, top-level function so it is testable without
/// mocking `connectivity_plus`'s platform channel.
bool isOffline(List<ConnectivityResult> results) =>
    results.isEmpty || results.every((r) => r == ConnectivityResult.none);

import 'dart:async';

import '../../../core/shell/sync_status.dart';
import 'attendance_queue.dart';

/// Closes T6's stub: `SyncIndicator`'s pending count is now the REAL number
/// of queued attendance marks, not a hardcoded 0.
///
/// Wraps the connectivity-derived source rather than replacing it, because
/// the two answer different questions — connectivity says whether we *can*
/// reach the server, the queue says whether there is anything *to* send.
/// The indicator needs both:
///
/// | connectivity | queue | shown |
/// |---|---|---|
/// | offline | any | `offline` + pending count |
/// | online | empty | `synced` |
/// | online | non-empty | `syncing` (a drain is due or in flight) |
class QueueSyncStatusSource implements SyncStatusSource {
  QueueSyncStatusSource({
    required this.connectivity,
    required this.queue,
  }) {
    _current = connectivity.current;
    _sub = connectivity.statusStream.listen((_) => refresh());
    refresh();
  }

  final SyncStatusSource connectivity;
  final AttendanceQueue queue;
  late StreamSubscription<SyncStatus> _sub;
  late SyncStatus _current;
  final _controller = StreamController<SyncStatus>.broadcast();

  /// Recomputes from connectivity + the queue. Called whenever connectivity
  /// changes and after every enqueue/drain, so the count the teacher sees is
  /// never stale.
  Future<void> refresh() async {
    final pending = await queue.pendingCount();
    final offline = connectivity.current.state == SyncState.offline;

    final next = offline
        ? SyncStatus.offline(pendingCount: pending)
        : pending > 0
            ? const SyncStatus.syncing()
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

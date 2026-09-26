import 'package:flutter/foundation.dart';

/// The three states [SyncIndicator] can show. Always visible in all three —
/// the previous build's indicator rendered NOTHING when healthy, which made
/// it untestable and meant nobody could tell working from broken.
enum SyncState { synced, syncing, offline }

@immutable
class SyncStatus {
  const SyncStatus({required this.state, this.pendingCount = 0});

  const SyncStatus.synced() : this(state: SyncState.synced);
  const SyncStatus.syncing() : this(state: SyncState.syncing);
  const SyncStatus.offline({int pendingCount = 0})
      : this(state: SyncState.offline, pendingCount: pendingCount);

  final SyncState state;

  /// Queued-but-unsent items. Meaningful only when [state] is
  /// [SyncState.offline]; zero otherwise.
  final int pendingCount;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.state == state &&
      other.pendingCount == pendingCount;

  @override
  int get hashCode => Object.hash(state, pendingCount);
}

/// SEAM FOR T6. T6 owns the network/offline-queue layer and will supply the
/// real implementation of this interface; T5 only defines the contract and
/// renders whatever it reports.
///
/// [current] must be synchronous so [SyncIndicator] can paint a correct first
/// frame without a loading flicker — sync status is local device state, never
/// a network round trip, so this is never a hardship to implement.
abstract interface class SyncStatusSource {
  SyncStatus get current;
  Stream<SyncStatus> get statusStream;
}

/// The T5 stand-in, used until T6 wires the real source. Always reports
/// synced. Exists so the shell and its tests do not depend on T6 landing
/// first — swapping this for the real source is a one-line change at the
/// call site, not a shell change.
class StaticSyncStatusSource implements SyncStatusSource {
  const StaticSyncStatusSource([
    this._status = const SyncStatus.synced(),
  ]);

  final SyncStatus _status;

  @override
  SyncStatus get current => _status;

  @override
  Stream<SyncStatus> get statusStream => Stream.value(_status);
}

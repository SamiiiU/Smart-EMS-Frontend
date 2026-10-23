import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/shell/sync_status.dart';
import 'attendance_queue.dart';
import 'attendance_repository.dart';

/// F13 (found on a physical Pixel 7 Pro): queued attendance was only sent right
/// after a register was submitted, so marks saved offline never reached the
/// server on their own. This drains the queue whenever it may now succeed:
/// app start and resume, connectivity regained, account change, and a bounded
/// backoff timer while anything is pending. One drain at a time; the queue
/// itself only ever removes server-acknowledged operations.
class AttendanceSyncCoordinator with WidgetsBindingObserver {
  AttendanceSyncCoordinator({
    required this.repository,
    required this.queue,
    required this.connectivity,
    this.accountChanges,
    this.minBackoff = const Duration(seconds: 15),
    this.maxBackoff = const Duration(minutes: 5),
  });

  final AttendanceRepository repository;
  final AttendanceQueue queue;
  final SyncStatusSource connectivity;
  final Listenable? accountChanges;
  final Duration minBackoff;
  final Duration maxBackoff;

  Future<void>? _inFlight;
  Timer? _retry;
  Duration _backoff = Duration.zero;
  StreamSubscription<SyncStatus>? _sub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sub = connectivity.statusStream.listen((s) {
      if (s.state != SyncState.offline) trigger();
    });
    accountChanges?.addListener(trigger);
    trigger();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) trigger();
  }

  /// Attempts a drain now (coalesced with any drain already running).
  Future<void> trigger() => _inFlight ??= _drain().whenComplete(() => _inFlight = null);

  Future<void> _drain() async {
    _retry?.cancel();
    if (await queue.pendingCount() == 0) {
      _backoff = Duration.zero;
      return;
    }
    try {
      final outcome = await repository.syncPending();
      if (outcome is SubmitSynced && await queue.pendingCount() == 0) {
        _backoff = Duration.zero;
        return;
      }
    } catch (_) {
      // Unknown outcome: the queue keeps the operation IDs; retry later.
    }
    _backoff = _backoff == Duration.zero
        ? minBackoff
        : Duration(milliseconds: (_backoff.inMilliseconds * 2).clamp(0, maxBackoff.inMilliseconds));
    _retry = Timer(_backoff, trigger);
  }

  void dispose() {
    _retry?.cancel();
    _sub?.cancel();
    accountChanges?.removeListener(trigger);
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/keyboard_tap_target.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/business_date.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_models.dart';
import '../domain/lock_window.dart';

AppStatus appStatusFor(AttendanceStatus s) => switch (s) {
  AttendanceStatus.present => AppStatus.present,
  AttendanceStatus.absent => AppStatus.absent,
  AttendanceStatus.late => AppStatus.late,
  AttendanceStatus.leave => AppStatus.leave,
  AttendanceStatus.excused => AppStatus.excused,
};

/// Bulk-first attendance marking: the whole section roster at once, one
/// submit (D-T8-02). Per-student correction becomes available only AFTER
/// submission, and only while the register is inside the lock window.
class AttendanceMarkingScreen extends StatefulWidget {
  const AttendanceMarkingScreen({
    required this.repository,
    required this.sectionId,
    required this.sectionLabel,
    required this.attendanceDate,
    this.lockWindow = const LockWindow.immediate(),
    this.clientUuidFactory,
    this.now,
    this.onExit,
    super.key,
  });

  /// How to leave when the register is embedded in a parent flow rather than
  /// pushed as a route (Today → register). When set, THIS screen alone decides
  /// whether back may leave: immediately when nothing is unsaved, otherwise
  /// only after "Leave" is confirmed (NOTE-QA-17: a parent PopScope used to
  /// close the register on the same back press, so "Keep marking" landed on
  /// Today and the unsaved marks were lost).
  final VoidCallback? onExit;

  final AttendanceRepository repository;
  final String sectionId;
  final String sectionLabel;
  final DateTime attendanceDate;

  /// Supplied by the caller, not read from a constant here, so the real
  /// configured value flows through unchanged once one exists.
  final LockWindow lockWindow;

  /// Injectable so tests are deterministic. Each mark needs a unique
  /// idempotency key the backend requires.
  final String Function()? clientUuidFactory;

  /// Injectable clock, so lock-window behaviour is testable without waiting
  /// for midnight.
  final DateTime Function()? now;

  @override
  State<AttendanceMarkingScreen> createState() =>
      AttendanceMarkingScreenState();
}

class AttendanceMarkingScreenState extends State<AttendanceMarkingScreen> {
  ScreenState<List<RosterStudent>> _roster =
      const ScreenState<List<RosterStudent>>.loading();

  /// Per-student selection. Defaults to PRESENT for every student: the
  /// backend has no default (every bulk row requires an explicit status),
  /// so the client must choose one, and marking the exceptions is far less
  /// work than marking the majority.
  final Map<String, AttendanceStatus> _selection = {};

  final Map<String, String> _pendingOperationIds = {};
  bool _submitting = false;
  bool _submitted = false;
  String? _notice;
  List<AttendanceConflict> _conflicts = const [];

  /// What the server already holds for this date, per student (BUG-QA-15).
  /// Rows equal to it are not resent: resending an unchanged mark only hits
  /// the 15-minute teacher lock and used to leave the register stuck.
  Map<String, AttendanceStatus> _serverHeld = const {};

  /// True when today's existing server marks could not be loaded (F15).
  bool _existingUnknown = false;

  /// RC finding (report 13 §11): marks of the SIGNED-IN account that are still
  /// in its offline queue for this section and date, by student. A reopened
  /// register used to show them as Unmarked, inviting a second mark under a new
  /// operation id. They are now shown as Pending and locked until they sync;
  /// the queue's owner scoping means another account's marks are never read.
  Map<String, AttendanceMark> _queued = const {};
  StreamSubscription<void>? _queueChanges;

  /// Overhaul M3: marks changed on this screen and not yet submitted.
  bool _dirty = false;
  String _query = '';

  /// Search appears only where scrolling becomes a burden.
  static const _searchThreshold = 10;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  bool get _isOpen => widget.lockWindow.isOpen(
    attendanceDate: widget.attendanceDate,
    now: _now,
  );

  String get _dateIso =>
      widget.attendanceDate.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _load();
    // Sync success/failure, another submit or an account change all write the
    // queue; re-resolve so Pending rows unlock once the server holds them.
    _queueChanges = widget.repository.queue.changes.listen(
      (_) => _refreshQueued(),
    );
  }

  @override
  void dispose() {
    _queueChanges?.cancel();
    super.dispose();
  }

  /// This account's queued marks for THIS section and date. Any failure to
  /// read (no signed-in account, account changed, unreadable vault) yields
  /// none: never another account's data, and never a guessed state.
  Future<Map<String, AttendanceMark>> _readQueued() async {
    try {
      final all = await widget.repository.queue.pending();
      return {
        for (final m in all)
          if (m.sectionId == widget.sectionId && m.attendanceDate == _dateIso)
            m.studentId: m,
      };
    } on Object {
      return const {};
    }
  }

  /// Re-resolves after the queue changed: rows that left the queue (synced or
  /// held for review) take the server's authoritative status again.
  Future<void> _refreshQueued() async {
    if (!mounted || _roster.data == null) return;
    final queued = await _readQueued();
    var server = _serverHeld;
    final released = _queued.keys
        .where((id) => !queued.containsKey(id))
        .toList();
    if (released.isNotEmpty) {
      try {
        server = await widget.repository.serverStatuses(
          sectionId: widget.sectionId,
          date: _dateIso,
        );
      } on Object {
        // Keep the last known server view; the rows simply stay as marked.
      }
    }
    if (!mounted) return;
    setState(() {
      _serverHeld = server;
      for (final id in released) {
        final held = server[id];
        if (held != null) {
          _selection[id] = held;
        } else {
          _selection.remove(id);
        }
      }
      for (final m in queued.values) {
        _selection[m.studentId] = m.status;
      }
      _queued = queued;
    });
  }

  String _newUuid() {
    final factory = widget.clientUuidFactory;
    if (factory != null) return factory();
    return const Uuid().v4();
  }

  Future<void> _load() async {
    setState(
      () => _roster = ScreenState<List<RosterStudent>>.loading(
        previous: _roster.data,
      ),
    );
    try {
      final students = await widget.repository.loadRoster(widget.sectionId);
      // F15 (physical device): show the marks the server ALREADY holds for this
      // date. Defaulting a reopened register to Present would let a resubmit
      // contradict real absences. If they cannot be loaded, say so plainly.
      var existing = const <String, AttendanceStatus>{};
      var existingKnown = true;
      try {
        existing = await widget.repository.serverStatuses(
          sectionId: widget.sectionId,
          date: _dateIso,
        );
      } on Object {
        existingKnown = false;
      }
      final queued = await _readQueued();
      if (!mounted) return;
      setState(() {
        _roster = ScreenState<List<RosterStudent>>.data(students);
        _existingUnknown = !existingKnown;
        _serverHeld = existing;
        _queued = queued;
        for (final s in students) {
          // A queued (unsynced) mark of this account is the latest intent for
          // this learner: show it, as Pending, instead of the server value.
          final waiting = queued[s.studentId];
          if (waiting != null) {
            _selection[s.studentId] = waiting.status;
            continue;
          }
          // QA-14 (approved 2026-10-14): a learner with no server record and
          // no deliberate tap is UNMARKED (absent from _selection), never a
          // silent Present.
          final held = existing[s.studentId];
          if (held != null) _selection.putIfAbsent(s.studentId, () => held);
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _roster = ScreenState<List<RosterStudent>>.failed(
          e is LoadFailure ? e : const LoadFailure(),
          cached: _roster.data,
        );
      });
    }
  }

  Future<void> submit() async {
    if (_submitting || !_isOpen) return;
    final students = _roster.data;
    if (students == null || students.isEmpty) return;

    setState(() {
      _submitting = true;
      _notice = null;
    });

    final marks = [
      for (final s in students)
        // Already queued for this account: it is sent by the queue, never
        // again from here under a new operation id.
        if (_selection[s.studentId] != null &&
            !_queued.containsKey(s.studentId) &&
            _serverHeld[s.studentId] != _selection[s.studentId])
          AttendanceMark(
            clientUuid: _pendingOperationIds.putIfAbsent(
              'mark:${s.studentId}:${_selection[s.studentId]}',
              _newUuid,
            ),
            sectionId: widget.sectionId,
            studentId: s.studentId,
            attendanceDate: _dateIso,
            status: _selection[s.studentId]!,
          ),
    ];

    if (marks.isEmpty) {
      // Everything already matches the server: nothing to send, and saying so
      // is clearer than a silent no-op.
      setState(() {
        _submitting = false;
        _submitted = true;
        _dirty = false;
        final left = _unmarkedCount();
        _notice = left > 0
            ? 'Nothing new to save. $left ${left == 1 ? 'learner is' : 'learners are'} still unmarked.'
            : 'Attendance is already up to date.';
      });
      return;
    }
    await _send(() => widget.repository.submitRegister(marks));
  }

  /// The correction path: a single student, through the single endpoint.
  Future<void> correct(String studentId, AttendanceStatus status) async {
    if (!_submitted || !_isOpen) return;
    setState(() {
      _selection[studentId] = status;
      _submitting = true;
      _notice = null;
    });

    await _send(
      () => widget.repository.correct(
        AttendanceMark(
          clientUuid: _pendingOperationIds.putIfAbsent(
            'correction:$studentId:$status',
            _newUuid,
          ),
          sectionId: widget.sectionId,
          studentId: studentId,
          attendanceDate: _dateIso,
          status: status,
          isCorrection: true,
        ),
      ),
    );
  }

  Future<void> _send(Future<SubmitOutcome> Function() action) async {
    try {
      final outcome = await action();
      _pendingOperationIds.clear();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
        _dirty = false;
        switch (outcome) {
          case SubmitQueued(:final pendingCount):
            // Not an error. The register is on disk and will go out later.
            _notice =
                'Saved offline. $pendingCount '
                '${pendingCount == 1 ? 'mark' : 'marks'} will sync when you '
                'are back online.';
          case SubmitSynced(:final conflicts):
            _serverHeld = {
              ..._serverHeld,
              for (final e in _selection.entries)
                if (!conflicts.any((c) => c.studentId == e.key)) e.key: e.value,
            };
            _conflicts = conflicts;
            final left = _unmarkedCount();
            // QA-14: a partial register says what is still missing; nothing was
            // invented for the unmarked learners.
            _notice = conflicts.isNotEmpty
                ? null
                : left > 0
                ? 'Attendance saved. $left ${left == 1 ? 'learner is' : 'learners are'} still unmarked.'
                : 'Attendance submitted.';
            for (final c in conflicts) {
              _selection[c.studentId] = c.serverStatus;
            }
        }
      });
    } on LoadFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _notice = failure.message ?? 'Could not submit attendance.';
      });
    } on Object catch (error) {
      // BUG-QA-15: any other failure (e.g. some marks not acknowledged) used
      // to escape this handler, leaving "Submitting…" on screen forever with
      // no message. The queue keeps unaccepted marks; say so plainly.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _notice = error is StateError
            ? error.message
            : 'Could not submit attendance. Your marks are kept on this device.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return PopScope(
      canPop: widget.onExit == null && !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_dirty && !await _confirmLeave()) return; // Keep marking: stay here
        if (!context.mounted) return;
        setState(() => _dirty = false);
        final exit = widget.onExit;
        if (exit != null) {
          exit();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: t.page,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.sectionLabel,
                      style: AppTypography.screenTitle.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      formatBusinessDate(context, _dateIso),
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // LOCKED: an explanation, not a silently disabled button.
              if (!_isOpen)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  child: InlineAlert(
                    tone: InlineAlertTone.warning,
                    message: widget.lockWindow.lockedReason(
                      attendanceDate: widget.attendanceDate,
                    ),
                  ),
                ),

              if (_existingUnknown)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                    vertical: AppSpacing.space4,
                  ),
                  child: InlineAlert(
                    tone: InlineAlertTone.warning,
                    message:
                        'Marks already recorded today could not be loaded. '
                        'Check each student before submitting; anything that '
                        'differs from the office record is sent for review.',
                  ),
                ),

              if (_conflicts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                    vertical: AppSpacing.space4,
                  ),
                  // Non-blocking: the teacher can keep working. The server kept
                  // its record and holds the teacher's mark for review (ADR-010).
                  child: InlineAlert(
                    tone: InlineAlertTone.info,
                    message: _conflicts.length == 1
                        ? '1 of your marks differs from the office record and was '
                              'sent for review. The office record stays until a '
                              'reviewer decides.'
                        : '${_conflicts.length} of your marks differ from the '
                              'office record and were sent for review. The office '
                              'record stays until a reviewer decides.',
                  ),
                ),

              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                    vertical: AppSpacing.space4,
                  ),
                  child: InlineAlert(
                    tone: InlineAlertTone.info,
                    message: _notice!,
                  ),
                ),

              if (_roster.data case final roster? when roster.isNotEmpty)
                _RegisterToolbar(
                  counts: _counts(roster),
                  unmarked: roster
                      .where((s) => _selection[s.studentId] == null)
                      .length,
                  pending: roster.where((s) => _isPending(s.studentId)).length,
                  total: roster.length,
                  showSearch: roster.length >= _searchThreshold,
                  onSearch: (q) => setState(() => _query = q),
                  onAllPresent:
                      _isOpen &&
                          !_submitting &&
                          !_submitted &&
                          roster.any((s) => _selection[s.studentId] == null)
                      ? () => _markAllPresent(roster)
                      : null,
                ),

              Expanded(
                child: ScreenStateBuilder<List<RosterStudent>>(
                  state: _roster,
                  onRetry: _load,
                  emptyTitle: 'No students enrolled',
                  emptyMessage:
                      'This section has no enrolled students, so there is '
                      'nothing to mark. Enrolment is managed by an '
                      'administrator.',
                  emptyIcon: Icons.groups_outlined,
                  data: (context, all) {
                    final students = _visible(all);
                    if (students.isEmpty) {
                      return Center(
                        child: Text(
                          'No student matches "$_query".',
                          style: AppTypography.bodyAdminMeta.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space6,
                      ),
                      itemCount: students.length,
                      itemBuilder: (context, i) {
                        final s = students[i];
                        return _RosterRow(
                          student: s,
                          status: _selection[s.studentId],
                          pending: _isPending(s.studentId),
                          queued: _queued.containsKey(s.studentId),
                          // Before submission the whole roster is editable;
                          // after it, edits go through the correction path.
                          // A queued learner is locked until the queue syncs.
                          enabled:
                              _isOpen &&
                              !_submitting &&
                              !_queued.containsKey(s.studentId),
                          onChanged: (next) {
                            if (_submitted) {
                              correct(s.studentId, next);
                            } else {
                              setState(() {
                                _selection[s.studentId] = next;
                                _dirty = true;
                              });
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              if (_isOpen)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.space6),
                  child: AppButton(
                    // Short by choice: 'Submit attendance' needs an ellipsis at
                    // a 2x text scale on a 360px phone, and a truncated verb is
                    // worse than a brief one. The screen title already says
                    // which register this is.
                    label: _submitting
                        ? 'Submitting…'
                        : _submitted
                        ? 'Submitted'
                        : 'Submit',
                    fullWidth: true,
                    onPressed: _submitting || _submitted || _roster.data == null
                        ? null
                        : submit,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _unmarkedCount() => (_roster.data ?? const <RosterStudent>[])
      .where((s) => _selection[s.studentId] == null)
      .length;

  /// A deliberate local mark the server does not hold yet (unsent or queued).
  bool _isPending(String studentId) {
    if (_queued.containsKey(studentId)) return true;
    final local = _selection[studentId];
    return local != null && _serverHeld[studentId] != local;
  }

  Map<AttendanceStatus, int> _counts(List<RosterStudent> roster) {
    final out = {for (final s in AttendanceStatus.values) s: 0};
    for (final st in roster) {
      final status = _selection[st.studentId];
      if (status != null) out[status] = out[status]! + 1;
    }
    return out;
  }

  List<RosterStudent> _visible(List<RosterStudent> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (s) =>
              s.fullName.toLowerCase().contains(q) ||
              (s.rollNumber ?? '').toLowerCase() == q,
        )
        .toList();
  }

  Future<void> _markAllPresent(List<RosterStudent> roster) async {
    // QA-14: only UNMARKED learners; a deliberate or saved status is never
    // overwritten in bulk (change those one by one).
    final changing = roster
        .where((s) => _selection[s.studentId] == null)
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark unmarked learners present?'),
        content: Text(
          '$changing unmarked ${changing == 1 ? 'learner' : 'learners'} will be '
          'set to Present. Learners you have already marked keep their status. '
          'Nothing is sent until you submit.',
        ),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
              ),
              AppButton(
                key: const Key('confirm-all-present'),
                label: 'Mark present',
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      for (final s in roster) {
        _selection.putIfAbsent(s.studentId, () => AttendanceStatus.present);
      }
      _dirty = true;
    });
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Leave without submitting?'),
          content: const Text(
            'Your marks on this register have not been submitted and will be lost.',
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space3,
              children: [
                AppButton(
                  label: 'Keep marking',
                  variant: AppButtonVariant.secondary,
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                ),
                AppButton(
                  key: const Key('confirm-leave'),
                  label: 'Leave',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
        ),
      ) ==
      true;
}

/// Overhaul M3: live totals, optional search and a guarded bulk action.
class _RegisterToolbar extends StatelessWidget {
  const _RegisterToolbar({
    required this.counts,
    required this.unmarked,
    required this.pending,
    required this.total,
    required this.showSearch,
    required this.onSearch,
    required this.onAllPresent,
  });

  final Map<AttendanceStatus, int> counts;
  final int unmarked;
  final int pending;
  final int total;
  final bool showSearch;
  final ValueChanged<String> onSearch;
  final VoidCallback? onAllPresent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = [
      for (final s in AttendanceStatus.values)
        if (counts[s]! > 0) s,
    ];
    final summary = [
      ...shown.map((s) => '${s.label} ${counts[s]}'),
      if (unmarked > 0) 'Unmarked $unmarked',
      if (pending > 0) 'Not yet saved $pending',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space6,
        0,
        AppSpacing.space6,
        AppSpacing.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: '$total students. $summary',
            excludeSemantics: true,
            child: Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '$total students',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                for (final s in shown)
                  Container(
                    key: Key('count-${s.wire}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space4,
                      vertical: AppSpacing.space2,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: t.border),
                    ),
                    child: Text(
                      '${s.label} ${counts[s]}',
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                if (unmarked > 0)
                  _CountChip(
                    key: const Key('count-unmarked'),
                    text: 'Unmarked $unmarked',
                    muted: true,
                  ),
                if (pending > 0)
                  _CountChip(
                    key: const Key('count-pending'),
                    text: 'Not yet saved $pending',
                    muted: true,
                  ),
              ],
            ),
          ),
          if (showSearch) ...[
            const SizedBox(height: AppSpacing.space4),
            AppTextField(
              label: 'Search by name or roll number',
              onChanged: onSearch,
            ),
          ],
          if (onAllPresent != null) ...[
            const SizedBox(height: AppSpacing.space3),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                key: const Key('mark-all-present'),
                label: 'Mark all present',
                variant: AppButtonVariant.secondary,
                onPressed: onAllPresent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.student,
    required this.status,
    required this.enabled,
    required this.onChanged,
    this.pending = false,
    this.queued = false,
  });

  final RosterStudent student;

  /// Null = Unmarked (QA-14).
  final AttendanceStatus? status;

  /// A deliberate mark the server does not hold yet.
  final bool pending;

  /// Waiting in this account's offline queue: shown, but not re-markable.
  final bool queued;
  final bool enabled;
  final ValueChanged<AttendanceStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: at a large text scale on a 360px phone the name
          // and the pill cannot share a line, and a Row overflows by a few
          // pixels rather than reflowing. Wrap lets the pill drop below.
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                student.rollNumber == null
                    ? student.fullName
                    : '${student.rollNumber}  ${student.fullName}',
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              if (status case final st?)
                StatusPill(status: appStatusFor(st))
              else
                _CountChip(
                  key: Key('unmarked-${student.studentId}'),
                  text: 'Unmarked',
                  muted: true,
                ),
              if (pending)
                _CountChip(
                  key: Key('pending-${student.studentId}'),
                  text: 'Pending',
                  muted: true,
                ),
            ],
          ),
          if (queued) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Saved on this device; waiting to sync. You can change it after it syncs.',
              key: Key('queued-note-${student.studentId}'),
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space3),
          // Wrap, not a Row: five options must reflow rather than overflow
          // at 360px or under a large text scale.
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final option in AttendanceStatus.values)
                _StatusChoice(
                  label: option.label,
                  // F10: each choice names its student for screen readers.
                  semanticLabel: '${option.label} for ${student.fullName}',
                  selected: option == status,
                  enabled: enabled,
                  onTap: () => onChanged(option),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          Divider(height: AppSpacing.space1, color: t.border),
        ],
      ),
    );
  }
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Selected uses a border + tint, never a saturated fill — consistent
    // with DesktopSidebar's active treatment, and it keeps the label on a
    // background the text tokens are actually verified against (D-36).
    final bg = selected ? t.primarySubtle : t.surface;
    final fg = enabled
        ? (selected ? t.textPrimary : t.textSecondary)
        : t.textDisabled;
    final border = selected ? t.primaryAccent : t.border;

    // DEF-18: was a bare GestureDetector (mouse/touch only). The shared target
    // adds Tab focus, Enter/Space activation and a keyboard focus ring, with the
    // same single "<status> for <learner>" announcement and selected state.
    return KeyboardTapTarget(
      label: semanticLabel,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      borderRadius: AppRadius.full,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: border),
        ),
        child: Text(label, style: AppTypography.fieldLabel.copyWith(color: fg)),
      ),
    );
  }
}

/// A small neutral pill for "Unmarked" / "Pending" / counts.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.text, this.muted = false, super.key});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: muted ? t.surfaceSunken : t.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: t.border),
      ),
      child: Text(
        text,
        style: AppTypography.bodyAdminMeta.copyWith(
          color: muted ? t.textSecondary : t.textPrimary,
        ),
      ),
    );
  }
}

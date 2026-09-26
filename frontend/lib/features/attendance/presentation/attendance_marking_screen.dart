import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
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
    super.key,
  });

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

  bool _submitting = false;
  bool _submitted = false;
  String? _notice;
  List<AttendanceConflict> _conflicts = const [];
  int _uuidCounter = 0;

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
  }

  String _newUuid() {
    final factory = widget.clientUuidFactory;
    if (factory != null) return factory();
    _uuidCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_uuidCounter';
  }

  Future<void> _load() async {
    setState(() => _roster = ScreenState<List<RosterStudent>>.loading(
          previous: _roster.data,
        ));
    try {
      final students = await widget.repository.loadRoster(widget.sectionId);
      if (!mounted) return;
      setState(() {
        _roster = ScreenState<List<RosterStudent>>.data(students);
        for (final s in students) {
          _selection.putIfAbsent(s.studentId, () => AttendanceStatus.present);
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
        AttendanceMark(
          clientUuid: _newUuid(),
          sectionId: widget.sectionId,
          studentId: s.studentId,
          attendanceDate: _dateIso,
          status: _selection[s.studentId] ?? AttendanceStatus.present,
        ),
    ];

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

    await _send(() => widget.repository.correct(
          AttendanceMark(
            clientUuid: _newUuid(),
            sectionId: widget.sectionId,
            studentId: studentId,
            attendanceDate: _dateIso,
            status: status,
            isCorrection: true,
          ),
        ));
  }

  Future<void> _send(Future<SubmitOutcome> Function() action) async {
    try {
      final outcome = await action();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
        switch (outcome) {
          case SubmitQueued(:final pendingCount):
            // Not an error. The register is on disk and will go out later.
            _notice = 'Saved offline. $pendingCount '
                '${pendingCount == 1 ? 'mark' : 'marks'} will sync when you '
                'are back online.';
          case SubmitSynced(:final conflicts):
            _conflicts = conflicts;
            _notice = conflicts.isEmpty ? 'Attendance submitted.' : null;
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
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
                    style: AppTypography.screenTitle
                        .copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    _dateIso,
                    style: AppTypography.bodyAdminMeta
                        .copyWith(color: t.textSecondary),
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

            if (_conflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                  vertical: AppSpacing.space4,
                ),
                // Non-blocking: the teacher can keep working. Server won,
                // and they are told exactly what changed.
                child: InlineAlert(
                  tone: InlineAlertTone.info,
                  message: _conflicts.length == 1
                      ? 'A more recent office record replaced 1 of your marks.'
                      : 'More recent office records replaced '
                          '${_conflicts.length} of your marks.',
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
                data: (context, students) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  itemCount: students.length,
                  itemBuilder: (context, i) {
                    final s = students[i];
                    return _RosterRow(
                      student: s,
                      status: _selection[s.studentId] ??
                          AttendanceStatus.present,
                      // Before submission the whole roster is editable;
                      // after it, edits go through the correction path.
                      enabled: _isOpen && !_submitting,
                      onChanged: (next) {
                        if (_submitted) {
                          correct(s.studentId, next);
                        } else {
                          setState(() => _selection[s.studentId] = next);
                        }
                      },
                    );
                  },
                ),
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
                  onPressed:
                      _submitting || _submitted || _roster.data == null
                          ? null
                          : submit,
                ),
              ),
          ],
        ),
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
  });

  final RosterStudent student;
  final AttendanceStatus status;
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
                style:
                    AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              StatusPill(status: appStatusFor(status)),
            ],
          ),
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
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
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

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
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
            child: Text(
              label,
              style: AppTypography.fieldLabel.copyWith(color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

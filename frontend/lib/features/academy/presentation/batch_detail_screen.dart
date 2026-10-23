import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/section_card.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';
import 'assessment_screen.dart';
import 'batch_fee_panel.dart';
import 'session_attendance_screen.dart';

/// One batch: overview and status, instructors, learners, weekly schedule
/// and dated sessions, assessments, and (for finance) the batch fee.
///
/// Management controls appear only where this account holds academy.manage
/// on the batch's campus; instructors see the teaching tabs. The server
/// re-checks every action, so a revoked instructor simply gets "not found".
class BatchDetailScreen extends StatelessWidget {
  const BatchDetailScreen({
    required this.repository,
    required this.batchId,
    this.feesAvailable = false,
    super.key,
  });
  final AcademyRepository repository;
  final String batchId;
  final bool feesAvailable;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AcademyLoader<BatchDetail>(
          load: () => repository.batch(batchId),
          emptyTitle: 'Batch not available',
          emptyMessage: 'This batch does not exist or is not available to you.',
          builder: (context, detail, reload) {
            final b = detail.batch;
            final manager = canOnCampus(context, academyManage, b.campusId);
            final finance =
                feesAvailable && canOnCampus(context, 'fee.manage', b.campusId);
            final tabs = <(String, Widget)>[
              (
                'Overview',
                _Overview(
                  repository: repository,
                  detail: detail,
                  manager: manager,
                  reload: reload,
                ),
              ),
              (
                'Learners',
                _Learners(repository: repository, batch: b, manager: manager),
              ),
              (
                'Sessions',
                _Sessions(
                  repository: repository,
                  detail: detail,
                  manager: manager,
                  reload: reload,
                ),
              ),
              (
                'Assessments',
                AssessmentsTab(
                  repository: repository,
                  batch: b,
                  canPublish:
                      manager &&
                      canOnCampus(context, 'exam.manage', b.campusId),
                ),
              ),
              if (finance)
                ('Fees', BatchFeePanel(repository: repository, batch: b)),
            ];
            return DefaultTabController(
              length: tabs.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BackButton(),
                      Expanded(
                        child: PageHeader(
                          title: '${b.courseName} · ${b.name}',
                          subtitle:
                              '${campusName(context, b.campusId)} · ${b.startDate} → ${b.endDate}',
                        ),
                      ),
                    ],
                  ),
                  TabBar(
                    isScrollable: true,
                    tabs: [for (final t in tabs) Tab(text: t.$1)],
                  ),
                  Expanded(
                    child: TabBarView(children: [for (final t in tabs) t.$2]),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.repository,
    required this.detail,
    required this.manager,
    required this.reload,
  });
  final AcademyRepository repository;
  final BatchDetail detail;
  final bool manager;
  final Future<void> Function() reload;

  Future<void> _status(BuildContext context, String status) async {
    final b = detail.batch;
    var reason = '';
    final ending = b.activeLearners > 0;
    final ok = await showFormDialog(
      context,
      title: status == 'cancelled'
          ? 'Cancel ${b.name}?'
          : status == 'closed'
          ? 'Close ${b.name}?'
          : 'Reopen ${b.name}?',
      submitLabel: status == 'cancelled'
          ? 'Cancel batch'
          : status == 'closed'
          ? 'Close batch'
          : 'Reopen',
      canSubmit: () => !ending || status == 'open' || reason.trim().length >= 3,
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ending && status != 'open') ...[
            InlineAlert(
              tone: InlineAlertTone.warning,
              message:
                  '${b.activeLearners} learners are enrolled. Their memberships will be marked '
                  '${status == 'closed' ? 'completed' : 'cancelled'}. Past attendance, marks and invoices are kept.'
                  '${status == 'cancelled' ? ' Future scheduled sessions without attendance are cancelled. This cannot be undone.' : ''}',
            ),
            const SizedBox(height: AppSpacing.space5),
            field(
              'Reason',
              reason,
              (v) => setState(() => reason = v),
              required: true,
            ),
          ] else if (status == 'cancelled')
            const InlineAlert(
              tone: InlineAlertTone.warning,
              message: 'A cancelled batch cannot be reopened.',
            ),
        ],
      ),
      submit: () => attempt(
        () => repository.setBatchStatus(
          b.id,
          status,
          endActiveEnrollments: ending && status != 'open',
          reason: reason.trim().isEmpty ? null : reason.trim(),
        ),
      ),
    );
    if (ok) await reload();
  }

  Future<void> _assign(BuildContext context) async {
    final staff = await loadForForm(
      context,
      () => repository.staff(detail.batch.campusId),
    );
    if (staff == null || !context.mounted) return;
    String? staffId;
    var role = 'primary';
    final ok = await showFormDialog(
      context,
      title: 'Assign an instructor',
      submitLabel: 'Assign',
      canSubmit: () => staffId != null,
      fields: (context, setState) => Column(
        children: [
          dropdown<String>('Staff member (this campus)', staffId, [
            for (final s in staff)
              (s.id, s.detail == null ? s.label : '${s.label} · ${s.detail}'),
          ], (v) => setState(() => staffId = v)),
          dropdown<String>('Role', role, const [
            ('primary', 'Primary instructor'),
            ('assistant', 'Assistant'),
          ], (v) => setState(() => role = v ?? 'primary')),
        ],
      ),
      submit: () => attempt(
        () => repository.assignInstructor(detail.batch.id, staffId!, role),
      ),
    );
    if (ok) await reload();
  }

  Future<void> _revoke(BuildContext context, Instructor i) async {
    if (!await confirmAction(
      context,
      title: 'Remove ${i.name}?',
      message:
          'They immediately lose access to this batch, its roster and attendance.',
      confirmLabel: 'Remove',
    )) {
      return;
    }
    final m = await attempt(
      () => repository.revokeInstructor(detail.batch.id, i.id),
    );
    if (!context.mounted) return;
    if (m != null) return showResult(context, m, error: true);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final b = detail.batch;
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        SectionCard(
          title: 'Batch',
          trailing: StatusChip(b.status),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Offering: ${b.offeringName}',
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textPrimary,
                ),
              ),
              Text(
                'Learners: ${b.activeLearners}${b.capacity == null ? '' : ' of ${b.capacity}'}',
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textSecondary,
                ),
              ),
              if (b.defaultRoom != null)
                Text(
                  'Room: ${b.defaultRoom}',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              if (manager && b.status != 'cancelled') ...[
                const SizedBox(height: AppSpacing.space5),
                Wrap(
                  spacing: AppSpacing.space4,
                  runSpacing: AppSpacing.space4,
                  children: [
                    if (b.status == 'closed')
                      AppButton(
                        label: 'Reopen',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _status(context, 'open'),
                      ),
                    if (b.status == 'open')
                      AppButton(
                        label: 'Close batch',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _status(context, 'closed'),
                      ),
                    AppButton(
                      label: 'Cancel batch',
                      variant: AppButtonVariant.ghost,
                      onPressed: () => _status(context, 'cancelled'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SectionCard(
          title: 'Instructors',
          trailing: manager && b.status != 'cancelled'
              ? AppButton(
                  label: 'Assign',
                  size: AppButtonSize.sm,
                  icon: Icons.add,
                  onPressed: () => _assign(context),
                )
              : null,
          child: detail.instructors.isEmpty
              ? const Text('No instructor assigned.')
              : Column(
                  children: [
                    for (final i in detail.instructors)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(i.name),
                        subtitle: Text(
                          i.role == 'primary'
                              ? 'Primary instructor'
                              : 'Assistant',
                        ),
                        trailing: manager
                            ? IconButton(
                                tooltip: 'Remove ${i.name}',
                                icon: const Icon(Icons.person_remove_outlined),
                                onPressed: () => _revoke(context, i),
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Active roster for instructors; managers also enrol learners (several
/// batches per learner are allowed — same campus only in v1) and end
/// memberships, and see the full membership history.
class _Learners extends StatefulWidget {
  const _Learners({
    required this.repository,
    required this.batch,
    required this.manager,
  });
  final AcademyRepository repository;
  final Batch batch;
  final bool manager;

  @override
  State<_Learners> createState() => _LearnersState();
}

class _LearnersState extends State<_Learners> {
  final _loader = GlobalKey<AcademyLoaderState<List<RosterEntry>>>();

  /// Kept per learner until the enrollment succeeds, so a retry after a lost
  /// response is replayed by the server instead of creating a duplicate.
  final Map<String, String> _pendingKeys = {};

  Future<void> _enroll() async {
    final loaded = await loadForForm(
      context,
      () async => (
        students: await widget.repository.students(widget.batch.campusId),
        roster: await widget.repository.roster(widget.batch.id),
      ),
    );
    if (loaded == null || !mounted) return;
    final candidates = loaded.students;
    // Already-active members are hidden from the picker (the server also refuses them).
    final enrolled = {for (final r in loaded.roster) r.studentId};
    String? studentId;
    final ok = await showFormDialog(
      context,
      title: 'Enrol a learner',
      submitLabel: 'Enrol',
      canSubmit: () => studentId != null,
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineAlert(
            tone: InlineAlertTone.info,
            message:
                'Only learners of ${campusName(context, widget.batch.campusId)} can join this batch. '
                'A learner may be in several batches at once.',
          ),
          const SizedBox(height: AppSpacing.space5),
          dropdown<String>('Learner', studentId, [
            for (final s in candidates)
              if (!enrolled.contains(s.id))
                (s.id, s.detail == null ? s.label : '${s.label} · ${s.detail}'),
          ], (v) => setState(() => studentId = v)),
        ],
      ),
      submit: () async {
        final key = _pendingKeys.putIfAbsent(
          studentId!,
          widget.repository.newKey,
        );
        final message = await attempt(
          () => widget.repository.enroll(widget.batch.id, studentId!, key),
        );
        if (message == null) _pendingKeys.remove(studentId);
        return message;
      },
    );
    if (ok) await _loader.currentState?.reload();
  }

  Future<void> _end(RosterEntry r) async {
    var status = 'withdrawn', reason = '';
    final ok = await showFormDialog(
      context,
      title: 'End ${r.name}\'s membership',
      submitLabel: 'End membership',
      canSubmit: () => reason.trim().length >= 3,
      fields: (context, setState) => Column(
        children: [
          dropdown<String>('Outcome', status, const [
            ('withdrawn', 'Withdrawn'),
            ('completed', 'Completed'),
            ('cancelled', 'Cancelled'),
          ], (v) => setState(() => status = v ?? 'withdrawn')),
          field(
            'Reason',
            reason,
            (v) => setState(() => reason = v),
            required: true,
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.endEnrollment(
          r.enrollmentId,
          status,
          reason.trim(),
        ),
      ),
    );
    if (ok) await _loader.currentState?.reload();
  }

  Future<void> _history() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Membership history'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: AcademyLoader<List<Enrollment>>(
          load: () => widget.repository.enrollmentHistory(widget.batch.id),
          isEmpty: (v) => v.isEmpty,
          emptyTitle: 'No memberships yet',
          emptyMessage:
              'Enrolled learners appear here, including ended memberships.',
          builder: (context, rows, _) => ListView(
            children: [
              for (final e in rows)
                ListTile(
                  title: Text(
                    'Enrolled ${e.enrolledOn}${e.endedOn == null ? '' : ' · ended ${e.endedOn}'}',
                  ),
                  subtitle: e.endReason == null ? null : Text(e.endReason!),
                  trailing: StatusChip(e.status),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final open = widget.batch.isOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.manager)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space6),
            child: Wrap(
              spacing: AppSpacing.space5,
              runSpacing: AppSpacing.space5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton(
                  label: 'Enrol learner',
                  icon: Icons.person_add_alt,
                  onPressed: open && !widget.batch.isFull ? _enroll : null,
                ),
                AppButton(
                  label: 'History',
                  variant: AppButtonVariant.secondary,
                  onPressed: _history,
                ),
                if (!open) const Text('Enrollment is closed for this batch.'),
                if (open && widget.batch.isFull)
                  const Text('The batch is full.'),
              ],
            ),
          ),
        Expanded(
          child: AcademyLoader<List<RosterEntry>>(
            key: _loader,
            load: () => widget.repository.roster(widget.batch.id),
            isEmpty: (v) => v.isEmpty,
            emptyTitle: 'No learners enrolled',
            emptyMessage: 'Enrolled learners of this batch appear here.',
            emptyIcon: Icons.groups_outlined,
            builder: (context, rows, _) => SizedBox.expand(
              child: AdaptiveDataView<RosterEntry>(
                rows: rows,
                semanticLabel: (r) =>
                    '${r.name}, admission ${r.admissionNumber}',
                columns: [
                  DataColumnSpec(
                    label: 'Learner',
                    value: (r) => r.name,
                    flex: 2,
                  ),
                  DataColumnSpec(
                    label: 'Admission no.',
                    value: (r) => r.admissionNumber,
                  ),
                  DataColumnSpec(label: 'Since', value: (r) => r.enrolledOn),
                ],
                rowActions: [
                  if (widget.manager) RowAction(label: 'End', onPressed: _end),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Weekly schedule (managers edit) and dated sessions for a 4-week window.
class _Sessions extends StatefulWidget {
  const _Sessions({
    required this.repository,
    required this.detail,
    required this.manager,
    required this.reload,
  });
  final AcademyRepository repository;
  final BatchDetail detail;
  final bool manager;
  final Future<void> Function() reload;

  @override
  State<_Sessions> createState() => _SessionsState();
}

class _SessionsState extends State<_Sessions> {
  final _loader = GlobalKey<AcademyLoaderState<List<Session>>>();
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));

  String get _fromIso => isoDate(_from);
  String get _toIso => isoDate(_from.add(const Duration(days: 27)));

  Future<void> _addSlot() async {
    var day = 1, start = '', end = '', room = '';
    final ok = await showFormDialog(
      context,
      title: 'Add a weekly slot',
      submitLabel: 'Add slot',
      canSubmit: () => isTime(start) && isTime(end) && start.compareTo(end) < 0,
      fields: (context, setState) => Column(
        children: [
          dropdown<int>('Day', day, [
            for (var d = 1; d <= 7; d++) (d, ScheduleSlot.days[d - 1]),
          ], (v) => setState(() => day = v ?? 1)),
          field(
            'Start (HH:MM)',
            start,
            (v) => setState(() => start = v),
            placeholder: '16:00',
            required: true,
            error: start.isEmpty || isTime(start) ? null : 'Use 24-hour HH:MM.',
          ),
          field(
            'End (HH:MM)',
            end,
            (v) => setState(() => end = v),
            placeholder: '17:00',
            required: true,
            error: end.isEmpty || isTime(end) ? null : 'Use 24-hour HH:MM.',
          ),
          field('Room (optional)', room, (v) => setState(() => room = v)),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.addSlot(
          widget.detail.batch.id,
          day,
          start.trim(),
          end.trim(),
          room.trim().isEmpty ? null : room.trim(),
        ),
      ),
    );
    if (ok) await widget.reload();
  }

  Future<void> _removeSlot(ScheduleSlot s) async {
    if (!await confirmAction(
      context,
      title: 'Remove ${s.dayLabel} ${s.start}?',
      message: 'Sessions already created stay as they are.',
      confirmLabel: 'Remove slot',
    )) {
      return;
    }
    final m = await attempt(
      () => widget.repository.removeSlot(widget.detail.batch.id, s.id),
    );
    if (!mounted) return;
    if (m != null) return showResult(context, m, error: true);
    await widget.reload();
  }

  Future<void> _generate() async {
    try {
      final r = await widget.repository.generateSessions(
        widget.detail.batch.id,
        _fromIso,
        _toIso,
      );
      if (!mounted) return;
      showResult(
        context,
        'Created ${r.created} sessions; ${r.existing} already existed'
        '${r.skipped > 0 ? '; ${r.skipped} skipped because of a clash (batch, instructor or room).' : '.'}',
      );
      await _loader.currentState?.reload();
    } on Object catch (e) {
      if (mounted) {
        showResult(context, AcademyRepository.explain(e), error: true);
      }
    }
  }

  Future<void> _edit([Session? s]) async {
    var date = s?.date ?? isoDate(DateTime.now()),
        start = s?.start ?? '',
        end = s?.end ?? '',
        room = s?.room ?? '';
    final ok = await showFormDialog(
      context,
      title: s == null
          ? 'Add a session'
          : 'Change session ${s.date} ${s.start}',
      submitLabel: s == null ? 'Add session' : 'Save',
      canSubmit: () =>
          isDate(date) &&
          isTime(start) &&
          isTime(end) &&
          start.compareTo(end) < 0,
      fields: (context, setState) => Column(
        children: [
          field(
            'Date',
            date,
            (v) => setState(() => date = v),
            placeholder: 'YYYY-MM-DD',
            required: true,
          ),
          field(
            'Start (HH:MM)',
            start,
            (v) => setState(() => start = v),
            required: true,
          ),
          field(
            'End (HH:MM)',
            end,
            (v) => setState(() => end = v),
            required: true,
          ),
          field('Room (optional)', room, (v) => setState(() => room = v)),
        ],
      ),
      submit: () => attempt(
        () => s == null
            ? widget.repository.createSession(
                widget.detail.batch.id,
                date.trim(),
                start.trim(),
                end.trim(),
                room.trim().isEmpty ? null : room.trim(),
              )
            : widget.repository.updateSession(
                s.id,
                date: date.trim() == s.date ? null : date.trim(),
                start: start.trim() == s.start ? null : start.trim(),
                end: end.trim() == s.end ? null : end.trim(),
                room: room.trim() == (s.room ?? '') ? null : room.trim(),
              ),
      ),
    );
    if (ok) await _loader.currentState?.reload();
  }

  Future<void> _cancel(Session s) async {
    if (!await confirmAction(
      context,
      title: 'Cancel the ${s.date} session?',
      message: 'Learners will see it as cancelled.',
      confirmLabel: 'Cancel session',
    )) {
      return;
    }
    final m = await attempt(
      () => widget.repository.updateSession(s.id, cancel: true),
    );
    if (!mounted) return;
    if (m != null) return showResult(context, m, error: true);
    await _loader.currentState?.reload();
  }

  void _attendance(Session s) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => SessionAttendanceScreen(
            repository: widget.repository,
            session: s,
            title:
                '${widget.detail.batch.courseName} · ${widget.detail.batch.name}',
          ),
        ),
      )
      .then((_) => _loader.currentState?.reload());

  @override
  Widget build(BuildContext context) {
    final b = widget.detail.batch;
    final schedule = widget.detail.schedule;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        SectionCard(
          title: 'Weekly schedule',
          trailing: widget.manager && b.isOpen
              ? AppButton(
                  label: 'Add slot',
                  size: AppButtonSize.sm,
                  icon: Icons.add,
                  onPressed: _addSlot,
                )
              : null,
          child: schedule.isEmpty
              ? const Text('No weekly slots yet.')
              : Wrap(
                  spacing: AppSpacing.space4,
                  runSpacing: AppSpacing.space4,
                  children: [
                    for (final s in schedule)
                      InputChip(
                        label: Text(
                          '${s.dayLabel} ${s.start}–${s.end}${s.room == null ? '' : ' · ${s.room}'}',
                        ),
                        onDeleted: widget.manager ? () => _removeSlot(s) : null,
                        deleteButtonTooltipMessage: 'Remove slot',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SectionCard(
          title: 'Sessions $_fromIso → $_toIso',
          trailing: Wrap(
            spacing: AppSpacing.space3,
            children: [
              IconButton(
                tooltip: 'Earlier',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _from = _from.subtract(const Duration(days: 28)),
                ),
              ),
              IconButton(
                tooltip: 'Later',
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    setState(() => _from = _from.add(const Duration(days: 28))),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.manager && b.isOpen)
                Wrap(
                  spacing: AppSpacing.space4,
                  runSpacing: AppSpacing.space4,
                  children: [
                    AppButton(
                      label: 'Add session',
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.secondary,
                      onPressed: _edit,
                    ),
                    if (schedule.isNotEmpty)
                      AppButton(
                        label: 'Create sessions from schedule',
                        size: AppButtonSize.sm,
                        variant: AppButtonVariant.secondary,
                        onPressed: _generate,
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.space5),
              SizedBox(
                height: 420,
                child: AcademyLoader<List<Session>>(
                  key: ValueKey('sessions-$_fromIso'),
                  load: () =>
                      widget.repository.sessions(b.id, _fromIso, _toIso),
                  isEmpty: (v) => v.isEmpty,
                  emptyTitle: 'No sessions in this period',
                  emptyMessage:
                      'Add sessions or create them from the weekly schedule.',
                  emptyIcon: Icons.event_outlined,
                  builder: (context, rows, _) => SizedBox.expand(
                    child: AdaptiveDataView<Session>(
                      rows: rows,
                      semanticLabel: (s) =>
                          'Session ${s.date} ${s.start} to ${s.end}, ${s.status}',
                      columns: [
                        DataColumnSpec(label: 'Date', value: (s) => s.date),
                        DataColumnSpec(
                          label: 'Time',
                          value: (s) => '${s.start}–${s.end}',
                        ),
                        DataColumnSpec(
                          label: 'Room',
                          value: (s) => s.room ?? '—',
                        ),
                        DataColumnSpec(
                          label: 'Status',
                          value: (s) => s.status,
                          cell: (s) => StatusChip(s.status),
                        ),
                      ],
                      rowActions: [
                        RowAction(
                          label: 'Attendance',
                          icon: Icons.fact_check_outlined,
                          onPressed: _attendance,
                          isVisible: (s) => !s.cancelled,
                        ),
                        if (widget.manager)
                          RowAction(
                            label: 'Change',
                            onPressed: _edit,
                            isVisible: (s) => !s.cancelled,
                          ),
                        if (widget.manager)
                          RowAction(
                            label: 'Cancel',
                            onPressed: _cancel,
                            isVisible: (s) => s.status == 'scheduled',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

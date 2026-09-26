import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../attendance/presentation/attendance_marking_screen.dart'
    show appStatusFor;
import '../../parent/data/parent_repository.dart';
import '../../parent/domain/parent_models.dart';
import '../domain/admin_models.dart';

/// One student, as the admin sees them.
///
/// **Only tabs whose content exists are rendered** (D-19). Attendance is
/// here because T9 already built its data layer and this reuses it whole;
/// fees, results and diary are NOT here, because nothing behind them is
/// built — an empty tab is a promise the app cannot keep.
class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({
    required this.student,
    required this.parentRepository,
    this.now,
    super.key,
  });

  final AdminStudent student;

  /// T9's repository, reused unchanged — the attendance history an admin
  /// needs is the same history a parent sees.
  final ParentRepository parentRepository;

  final DateTime Function()? now;

  /// How far back the attendance tab reaches. Same window T9 chose, for the
  /// same reason: the endpoint requires a `from`, so some window must be
  /// picked, and 30 days is what the parent view already established.
  static const int windowDays = 30;

  @override
  State<StudentProfileScreen> createState() => StudentProfileScreenState();
}

class StudentProfileScreenState extends State<StudentProfileScreen> {
  ScreenState<List<AttendanceDay>> _attendance =
      const ScreenState<List<AttendanceDay>>.loading();

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _attendance =
        ScreenState<List<AttendanceDay>>.loading(previous: _attendance.data));
    try {
      final to = _now;
      final days = await widget.parentRepository.loadAttendance(
        studentId: widget.student.id,
        from: to.subtract(
          const Duration(days: StudentProfileScreen.windowDays),
        ),
        to: to,
      );
      if (!mounted) return;
      setState(
          () => _attendance = ScreenState<List<AttendanceDay>>.data(days));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _attendance = ScreenState<List<AttendanceDay>>.failed(
            e is LoadFailure ? e : const LoadFailure(),
            cached: _attendance.data,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final student = widget.student;

    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(
        backgroundColor: t.surface,
        surfaceTintColor: t.surface,
        iconTheme: IconThemeData(color: t.textPrimary),
        title: Text(
          student.fullName,
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: _Details(student: student),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space6,
              ),
              child: Text(
                'Attendance · last ${StudentProfileScreen.windowDays} days',
                style:
                    AppTypography.overline.copyWith(color: t.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Expanded(
              child: ScreenStateBuilder<List<AttendanceDay>>(
                state: _attendance,
                onRetry: _loadAttendance,
                emptyTitle: 'No attendance recorded',
                emptyMessage:
                    'Nothing has been marked for ${student.fullName} in the '
                    'last ${StudentProfileScreen.windowDays} days.',
                emptyIcon: Icons.event_busy_outlined,
                data: (context, days) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  itemCount: days.length,
                  itemBuilder: (context, i) => _DayRow(day: days[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.student});

  final AdminStudent student;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Wrap(
        spacing: AppSpacing.space6,
        runSpacing: AppSpacing.space3,
        children: [
          _Field(label: 'Admission no.', value: student.admissionNumber),
          _Field(
            label: 'Class',
            value: student.classLabel ?? 'Not enrolled',
          ),
          _Field(label: 'Status', value: student.status ?? '—'),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.overline.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          value,
          style: AppTypography.personName.copyWith(color: t.textPrimary),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints:
          const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            day.date,
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          StatusPill(status: appStatusFor(day.status)),
        ],
      ),
    );
  }
}

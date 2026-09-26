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
import '../data/parent_repository.dart';
import '../domain/parent_models.dart';

/// A child's attendance over a window of days.
///
/// **Read-only.** Parents have `attendance.view` and NOT `attendance.mark`
/// (confirmed from the real parent JWT), so there is no marking affordance
/// here — offering one would be a control the backend would reject.
///
/// The window is fixed at the last 30 days rather than offering a date
/// picker: the endpoint requires a `from`, so *some* window must be chosen,
/// and a picker is only worth building once there is a reason to look
/// further back than a month.
class ChildAttendanceScreen extends StatefulWidget {
  const ChildAttendanceScreen({
    required this.repository,
    required this.child,
    this.now,
    super.key,
  });

  final ParentRepository repository;
  final GuardianChild child;
  final DateTime Function()? now;

  /// How far back the view reaches.
  static const int windowDays = 30;

  @override
  State<ChildAttendanceScreen> createState() => ChildAttendanceScreenState();
}

class ChildAttendanceScreenState extends State<ChildAttendanceScreen> {
  ScreenState<List<AttendanceDay>> _state =
      const ScreenState<List<AttendanceDay>>.loading();

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state =
        ScreenState<List<AttendanceDay>>.loading(previous: _state.data));
    try {
      final to = _now;
      final days = await widget.repository.loadAttendance(
        studentId: widget.child.studentId,
        from: to.subtract(
          const Duration(days: ChildAttendanceScreen.windowDays),
        ),
        to: to,
      );
      if (!mounted) return;
      setState(() => _state = ScreenState<List<AttendanceDay>>.data(days));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = ScreenState<List<AttendanceDay>>.failed(
            e is LoadFailure ? e : const LoadFailure(),
            cached: _state.data,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(
        backgroundColor: t.surface,
        surfaceTintColor: t.surface,
        title: Text(
          widget.child.fullName,
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
        iconTheme: IconThemeData(color: t.textPrimary),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space5,
                AppSpacing.space6,
                AppSpacing.space3,
              ),
              child: Text(
                'Last ${ChildAttendanceScreen.windowDays} days',
                style: AppTypography.overline.copyWith(color: t.textSecondary),
              ),
            ),
            Expanded(
              child: ScreenStateBuilder<List<AttendanceDay>>(
                state: _state,
                onRetry: _load,
                emptyTitle: 'No attendance recorded',
                emptyMessage:
                    'Nothing has been marked for ${widget.child.fullName} in '
                    'the last ${ChildAttendanceScreen.windowDays} days.',
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

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(
        minHeight: AppSizing.listRowMinHeight,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      // Wrap, not Row: the date and pill cannot share a line at a large
      // text scale on a 360px phone, and a Row would overflow rather than
      // reflow — the same trap the roster row hit in T8.
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

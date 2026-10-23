import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/business_date.dart';
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
///
/// M5: only the server's records are shown — one row per recorded day with
/// its own status. No percentages or totals are derived here.
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

  /// Widest the history column grows on desktop.
  static const double maxContentWidth = 720;

  @override
  State<ChildAttendanceScreen> createState() => ChildAttendanceScreenState();
}

class ChildAttendanceScreenState extends State<ChildAttendanceScreen> {
  ScreenState<List<AttendanceDay>> _state =
      const ScreenState<List<AttendanceDay>>.loading();

  /// The window actually requested, so the header names exactly that period.
  late DateTime _from;
  late DateTime _to;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _to = _now;
    _from = _to.subtract(
      const Duration(days: ChildAttendanceScreen.windowDays),
    );
    _load();
  }

  Future<void> _load() async {
    final to = _now;
    final from = to.subtract(
      const Duration(days: ChildAttendanceScreen.windowDays),
    );
    setState(() {
      _from = from;
      _to = to;
      _state = ScreenState<List<AttendanceDay>>.loading(previous: _state.data);
    });
    try {
      final days = await widget.repository.loadAttendance(
        studentId: widget.child.studentId,
        from: from,
        to: to,
      );
      if (!mounted) return;
      setState(() => _state = ScreenState<List<AttendanceDay>>.data(days));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ScreenState<List<AttendanceDay>>.failed(
          e is LoadFailure ? e : const LoadFailure(),
          cached: _state.data,
        ),
      );
    }
  }

  static String _isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final period =
        '${formatBusinessDate(context, _isoDay(_from))} – '
        '${formatBusinessDate(context, _isoDay(_to))}';

    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(
        backgroundColor: t.surface,
        surfaceTintColor: t.surface,
        title: Text(
          'Attendance',
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
        iconTheme: IconThemeData(color: t.textPrimary),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ChildAttendanceScreen.maxContentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(child: widget.child, period: period),
                Expanded(
                  child: ScreenStateBuilder<List<AttendanceDay>>(
                    state: _state,
                    onRetry: _load,
                    emptyTitle: 'No attendance recorded',
                    emptyMessage:
                        'Nothing has been marked for ${widget.child.fullName} '
                        'in the last ${ChildAttendanceScreen.windowDays} days.',
                    emptyIcon: Icons.event_busy_outlined,
                    data: (context, days) => ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.space6,
                        0,
                        AppSpacing.space6,
                        AppSpacing.space6,
                      ),
                      itemCount: days.length,
                      itemBuilder: (context, i) => _DayRow(day: days[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who and which period, so a parent with several children can never
/// mistake whose history this is.
class _Header extends StatelessWidget {
  const _Header({required this.child, required this.period});

  final GuardianChild child;
  final String period;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final klass = child.classLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space6,
        AppSpacing.space6,
        AppSpacing.space6,
        AppSpacing.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              child.fullName,
              key: const Key('attendance-child-name'),
              style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
            ),
          ),
          if (klass != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              klass,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          Text(
            'Last ${ChildAttendanceScreen.windowDays} days · $period',
            style: AppTypography.overline.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final AttendanceDay day;

  /// Weekday of a business date, read as a plain calendar day (no timezone).
  static String? weekday(BuildContext context, String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso.trim());
    if (m == null) return null;
    final date = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    final locale =
        Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en';
    try {
      return DateFormat.EEEE(locale).format(date);
    } on Object {
      return DateFormat.EEEE('en').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final date = formatBusinessDate(context, day.date);
    final dow = weekday(context, day.date);

    // One node per day: "Wednesday, Oct 14, 2026: Present".
    return Semantics(
      container: true,
      label: '${dow == null ? '' : '$dow, '}$date: ${day.status.label}',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.space3),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space5,
          vertical: AppSpacing.space4,
        ),
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
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: AppTypography.personName.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                if (dow != null)
                  Text(
                    dow,
                    style: AppTypography.bodyAdminMeta.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
              ],
            ),
            StatusPill(status: appStatusFor(day.status)),
          ],
        ),
      ),
    );
  }
}

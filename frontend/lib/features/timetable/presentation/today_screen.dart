import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/timetable_repository.dart';

/// The teacher's home tab: today's periods, tapping through into that
/// section's register.
///
/// Navigation was blocked through T8 because the timetable API returned no
/// `sectionId`. Ali's 2026-08-10 change added it, so the rows are live and
/// the interim section picker is gone.
///
/// A period with no `sectionId` (a break, a free period) stays non-tappable
/// rather than guessing — opening the wrong class's register is worse than
/// an inert row.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    required this.repository,
    required this.staffId,
    this.onOpenRegister,
    this.now,
    this.title = 'Today',
    super.key,
  });

  /// The heading. The Diary tab (T11) reuses this exact list — same periods,
  /// same break/free-period inertness — under its own name, rather than a
  /// second copy of the timetable screen.
  final String title;

  final TimetableRepository repository;

  /// Opens the register for a period. Null makes every row inert — used by
  /// tests that only care about rendering.
  final void Function(TimetablePeriod period)? onOpenRegister;

  /// Null when the signed-in user has no staff record — an admin, for
  /// instance. There is then no "my teaching day" to show at all.
  final String? staffId;

  final DateTime Function()? now;

  @override
  State<TodayScreen> createState() => TodayScreenState();
}

class TodayScreenState extends State<TodayScreen> {
  ScreenState<List<TimetablePeriod>> _state =
      const ScreenState<List<TimetablePeriod>>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final staffId = widget.staffId;
    if (staffId == null) {
      setState(() => _state =
          const ScreenState<List<TimetablePeriod>>.data([], isEmpty: true));
      return;
    }
    setState(() => _state = ScreenState<List<TimetablePeriod>>.loading(
          previous: _state.data,
        ));
    try {
      final periods = await widget.repository.todayFor(staffId);
      if (!mounted) return;
      setState(() =>
          _state = ScreenState<List<TimetablePeriod>>.data(periods));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = ScreenState<List<TimetablePeriod>>.failed(
            e is LoadFailure ? e : const LoadFailure(),
            cached: _state.data,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final now = widget.now?.call() ?? DateTime.now();

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Text(
                widget.title,
                style:
                    AppTypography.screenTitle.copyWith(color: t.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            Expanded(
              child: ScreenStateBuilder<List<TimetablePeriod>>(
                state: _state,
                onRetry: _load,
                emptyTitle: widget.staffId == null
                    ? 'No teaching schedule'
                    : 'Nothing scheduled today',
                emptyMessage: widget.staffId == null
                    ? 'This account is not linked to a staff record, so it '
                        'has no teaching timetable.'
                    : 'You have no periods on your timetable for today.',
                emptyIcon: Icons.event_available_outlined,
                data: (context, periods) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  itemCount: periods.length,
                  itemBuilder: (context, i) {
                    final period = periods[i];
                    final open = widget.onOpenRegister;
                    return _PeriodRow(
                      period: period,
                      current: period.isCurrent(now),
                      // Inert without a sectionId: a break or free period
                      // has none, and guessing one would open the wrong
                      // class's register.
                      onTap: (open == null || period.sectionId == null)
                          ? null
                          : () => open(period),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.period,
    required this.current,
    required this.onTap,
  });

  final TimetablePeriod period;

  /// The period happening right now — the one a teacher unlocking their
  /// phone is looking for.
  final bool current;

  /// Null for periods with no section (breaks, free periods).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);
    if (onTap == null) return card;

    return Semantics(
      button: true,
      label: 'Take attendance for ${period.sectionName ?? 'this period'}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: card),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final t = context.tokens;

    // The left accent is a STRIPE, not a thick BorderSide. Flutter asserts
    // on a non-uniform Border combined with a borderRadius ("The following
    // is not uniform"), which crashed at paint time the moment a period was
    // actually current — invisible until a test rendered one.
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (current)
                Container(
                  width: AppSizing.sidebarActiveBorderWidth,
                  color: t.primaryAccent,
                ),
              Expanded(
                child: Container(
                  color: current ? t.primarySubtle : t.surface,
                  padding: const EdgeInsets.all(AppSpacing.space5),
                  child: _content(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final t = context.tokens;
    return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [period.sectionName, period.subjectName]
                      .whereType<String>()
                      .join(' · '),
                  style: AppTypography.cardHeading
                      .copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  '${period.periodName} · ${period.timeLabel}',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          if (current)
            Text(
              'Now',
              style: AppTypography.overline.copyWith(color: t.textPrimary),
            ),
          // Only where the row actually leads somewhere — a chevron on an
          // inert break row would be a false affordance (D-19).
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.space3),
            Icon(Icons.chevron_right, color: t.textSecondary),
          ],
        ],
    );
  }
}

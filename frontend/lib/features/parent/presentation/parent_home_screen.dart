import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../../../core/widgets/states/error_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../attendance/presentation/attendance_marking_screen.dart'
    show appStatusFor;
import '../data/parent_repository.dart';
import 'child_progress_details.dart';
import '../domain/parent_models.dart';
import 'child_attendance_screen.dart';

/// The parent's landing tab: "is my child marked present today?".
///
/// Answers that in one glance, then offers the history behind it. The
/// guardian lookup and the child's day are two calls, so the guardian is
/// resolved first — without it there is no child to ask about.
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({
    required this.repository,
    this.now,
    super.key,
  });

  final ParentRepository repository;
  final DateTime Function()? now;

  @override
  State<ParentHomeScreen> createState() => ParentHomeScreenState();
}

class ParentHomeScreenState extends State<ParentHomeScreen> {
  ScreenState<GuardianProfile> _guardian =
      const ScreenState<GuardianProfile>.loading();
  ScreenState<ChildToday> _today = const ScreenState<ChildToday>.loading();

  GuardianChild? _selected;

  /// True when `/api/guardians/me` returned 404: a real login with no
  /// guardian record (D-17). Not an error, and never offered a retry.
  bool _notLinked = false;

  @override
  void initState() {
    super.initState();
    _loadGuardian();
  }

  Future<void> _loadGuardian() async {
    setState(() {
      _guardian = ScreenState<GuardianProfile>.loading(previous: _guardian.data);
      _notLinked = false;
    });
    try {
      final profile = await widget.repository.loadGuardian();
      if (!mounted) return;
      setState(() {
        _guardian = ScreenState<GuardianProfile>.data(
          profile,
          // A guardian with no children is a real, loaded profile — the
          // EMPTY state, not a failure.
          isEmpty: profile.children.isEmpty,
        );
        _selected = profile.children.isEmpty ? null : profile.children.first;
      });
      if (_selected != null) await _loadToday(_selected!);
    } on LoadFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _notLinked = failure.isNotLinked;
        _guardian = ScreenState<GuardianProfile>.failed(
          failure,
          cached: _guardian.data,
        );
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _guardian = ScreenState<GuardianProfile>.failed(
            const LoadFailure(),
            cached: _guardian.data,
          ));
    }
  }

  Future<void> _loadToday(GuardianChild child) async {
    setState(() => _today = const ScreenState<ChildToday>.loading());
    try {
      final today = await widget.repository.loadToday(child.studentId);
      if (!mounted) return;
      setState(() => _today = ScreenState<ChildToday>.data(
            today,
            // A single record is never "empty" — without this the resolver
            // would throw, since ChildToday is not an Iterable (D-39).
            isEmpty: false,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _today = ScreenState<ChildToday>.failed(
            e is LoadFailure ? e : const LoadFailure(),
          ));
    }
  }

  void selectChild(GuardianChild child) {
    if (child.studentId == _selected?.studentId) return;
    setState(() => _selected = child);
    _loadToday(child);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // D-17: the login is valid, the person record is missing. The parent
    // cannot fix this, so there is no retry — it names who can.
    if (_notLinked) {
      return const Scaffold(body: UnlinkedProfileState());
    }

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ScreenStateBuilder<GuardianProfile>(
          state: _guardian,
          onRetry: _loadGuardian,
          emptyTitle: 'No children linked',
          emptyMessage:
              'Your account is not linked to any student yet. Your '
              'institution’s administrator can add them.',
          emptyIcon: Icons.family_restroom_outlined,
          data: (context, profile) => _body(context, profile),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, GuardianProfile profile) {
    final t = context.tokens;
    final selected = _selected;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Text(
          profile.fullName.isEmpty ? 'Your children' : profile.fullName,
          style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space6),

        // Only shown when there is a choice to make. One child needs no
        // switcher, and rendering a single-option picker would be noise.
        if (profile.hasMultipleChildren) ...[
          _ChildSwitcher(
            children: profile.children,
            selectedId: selected?.studentId,
            onSelect: selectChild,
          ),
          const SizedBox(height: AppSpacing.space6),
        ],

        if (selected != null) ...[
          // D-29: the parent status reveal, 300ms with scale 0.97 → 1. This
          // is the one thing they opened the app for, so it should RESOLVE
          // rather than appear — and it is the only scale in the product
          // outside the submit confirmation.
          MotionReveal(
            duration: AppMotion.heroReveal,
            scaleFrom: AppMotion.heroScaleFrom,
            offset: 0,
            child: _TodayCard(
              child: selected,
              state: _today,
              onRetry: () => _loadToday(selected),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          _HistoryLink(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChildAttendanceScreen(
                  repository: widget.repository,
                  child: selected,
                  now: widget.now,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Horizontal child selector. Same visual weight as a tab, deliberately —
/// switching child is a lateral move, not a decision worth a modal.
class _ChildSwitcher extends StatelessWidget {
  const _ChildSwitcher({
    required this.children,
    required this.selectedId,
    required this.onSelect,
  });

  final List<GuardianChild> children;
  final String? selectedId;
  final ValueChanged<GuardianChild> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space3,
      children: [
        for (final child in children)
          _ChildChip(
            child: child,
            selected: child.studentId == selectedId,
            onTap: () => onSelect(child),
          ),
      ],
    );
  }
}

class _ChildChip extends StatelessWidget {
  const _ChildChip({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final GuardianChild child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Border + tint, never a saturated fill — consistent with the sidebar's
    // and the status chips' active treatment, and it keeps the label on a
    // background the text tokens are verified against (D-36).
    final bg = selected ? t.primarySubtle : t.surface;
    final fg = selected ? t.textPrimary : t.textSecondary;
    final border = selected ? t.primaryAccent : t.border;

    return Semantics(
      button: true,
      selected: selected,
      label: child.fullName,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space3,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: border),
            ),
            child: Text(
              child.fullName,
              style: AppTypography.fieldLabel.copyWith(color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer to the question the parent opened the app to ask.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.child,
    required this.state,
    required this.onRetry,
  });

  final GuardianChild child;
  final ScreenState<ChildToday> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            child.fullName,
            style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
          ),
          if (child.classLabel != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              child.classLabel!,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space5),
          ScreenStateBuilder<ChildToday>(
            state: state,
            onRetry: onRetry,
            skeleton: const LoadingSkeletonLine(),
            emptyTitle: 'No record',
            emptyMessage: 'Nothing recorded for today yet.',
            data: (context, today) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusRow(context, today),
                // T16: the rest of what this endpoint has always returned.
                // T9 read only the attendance status because the screens
                // that give the other fields meaning did not exist yet.
                ChildProgressDetails(today: today),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(BuildContext context, ChildToday today) {
    final t = context.tokens;

    // NOT marked is its own answer. Rendering it as absent would tell a
    // parent their child missed school because a teacher is running late.
    if (!today.isMarked) {
      return Row(
        children: [
          Icon(Icons.schedule_outlined, color: t.textSecondary),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              'Attendance has not been taken yet today.',
              style: AppTypography.bodyParentStudent.copyWith(
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        StatusPill(status: appStatusFor(today.status!)),
        const SizedBox(width: AppSpacing.space4),
        Expanded(
          child: Text(
            'Today, ${today.date}',
            style: AppTypography.bodyAdminMeta.copyWith(
              color: t.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A single-line skeleton for the status slot — the default list-row
/// skeleton would imply a list is coming.
class LoadingSkeletonLine extends StatelessWidget {
  const LoadingSkeletonLine({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: AppSpacing.space8,
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

class _HistoryLink extends StatelessWidget {
  const _HistoryLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      label: 'View attendance history',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.space5),
            constraints: const BoxConstraints(
              minHeight: AppSizing.listRowMinHeight,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: t.border, width: AppSizing.borderThin),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Attendance history',
                    style: AppTypography.cardHeading.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: t.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

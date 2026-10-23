import 'package:flutter/material.dart';

import '../../../core/widgets/business_date.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/keyboard_tap_target.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../../../core/widgets/states/error_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../attendance/presentation/attendance_marking_screen.dart'
    show appStatusFor;
import '../../academy/data/academy_repository.dart';
import '../data/parent_repository.dart';
import 'academy_child_summary.dart';
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
    this.academy,
    this.now,
    super.key,
  });

  final ParentRepository repository;

  /// Set only for an ACADEMY-profile institution: each child's card then also
  /// shows their Academy batches, today's sessions and published results, and
  /// an Academy-only child (no class enrollment) is shown instead of an error.
  final AcademyRepository? academy;
  final DateTime Function()? now;

  @override
  State<ParentHomeScreen> createState() => ParentHomeScreenState();
}

class ParentHomeScreenState extends State<ParentHomeScreen> {
  ScreenState<GuardianProfile> _guardian =
      const ScreenState<GuardianProfile>.loading();
  ScreenState<ChildDay> _today = const ScreenState<ChildDay>.loading();

  GuardianChild? _selected;

  /// ADR-011 "All children" overview (when [_selected] is null and there are
  /// several children). Keyed per child so nothing is shared across children.
  final Map<String, ScreenState<ChildDay>> _overview = {};

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
      _guardian = ScreenState<GuardianProfile>.loading(
        previous: _guardian.data,
      );
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
        // Several children open on the All-children overview; one child
        // opens directly. Only officially linked children are listed.
        _selected = profile.children.length == 1
            ? profile.children.single
            : null;
      });
      if (_selected != null) {
        await _loadToday(_selected!);
      } else {
        await _loadOverview(profile.children);
      }
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
      setState(
        () => _guardian = ScreenState<GuardianProfile>.failed(
          const LoadFailure(),
          cached: _guardian.data,
        ),
      );
    }
  }

  Future<void> _loadToday(GuardianChild child) async {
    setState(() => _today = const ScreenState<ChildDay>.loading());
    try {
      final today = ChildDay(
        await widget.repository.loadToday(child.studentId),
      );
      // A late answer for a child who is no longer selected must never be
      // shown under another child.
      if (!mounted || _selected?.studentId != child.studentId) return;
      setState(
        () => _today = ScreenState<ChildDay>.data(
          today,
          // A single record is never "empty" — without this the resolver
          // would throw, since ChildToday is not an Iterable (D-39).
          isEmpty: false,
        ),
      );
    } on Object catch (e) {
      if (!mounted || _selected?.studentId != child.studentId) return;
      setState(
        () => _today = ScreenState<ChildDay>.failed(
          e is LoadFailure ? e : const LoadFailure(),
        ),
      );
    }
  }

  Future<void> _loadOverview(List<GuardianChild> children) async {
    setState(() {
      _overview
        ..clear()
        ..addAll({
          for (final c in children)
            c.studentId: const ScreenState<ChildDay>.loading(),
        });
    });
    await Future.wait([
      for (final c in children)
        widget.repository
            .loadToday(c.studentId)
            .then(
              (today) {
                if (mounted && _overview.containsKey(c.studentId)) {
                  setState(
                    () => _overview[c.studentId] = ScreenState<ChildDay>.data(
                      ChildDay(today),
                      isEmpty: false,
                    ),
                  );
                }
              },
              onError: (Object e) {
                if (mounted && _overview.containsKey(c.studentId)) {
                  setState(
                    () => _overview[c.studentId] = ScreenState<ChildDay>.failed(
                      e is LoadFailure ? e : const LoadFailure(),
                    ),
                  );
                }
              },
            ),
    ]);
  }

  void selectChild(GuardianChild child) {
    if (child.studentId == _selected?.studentId) return;
    setState(() {
      _selected = child;
      _today = const ScreenState<ChildDay>.loading();
    });
    _loadToday(child);
  }

  void showAllChildren(List<GuardianChild> children) {
    if (_selected == null) return;
    setState(() => _selected = null);
    _loadOverview(children);
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
          emptyTitle: 'No verified child access',
          emptyMessage:
              'No child relationship currently grants browsing access. '
              'Ask your institution to review pending, contact-only, suspended or revoked relationships.',
          emptyIcon: Icons.family_restroom_outlined,
          data: (context, profile) => _body(context, profile),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, GuardianProfile profile) {
    final t = context.tokens;
    final selected = _selected;

    // M5: a readable column on wide screens; phones keep the full width.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: _list(context, profile, selected, t),
      ),
    );
  }

  /// Widest the landing column grows on desktop.
  static const double maxContentWidth = 840;

  Widget _list(
    BuildContext context,
    GuardianProfile profile,
    GuardianChild? selected,
    SmartEmsTokens t,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Semantics(
          header: true,
          child: Text(
            profile.fullName.isEmpty ? 'Your children' : profile.fullName,
            style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),

        // Only shown when there is a choice to make. One child needs no
        // switcher, and rendering a single-option picker would be noise.
        if (profile.hasMultipleChildren) ...[
          _ChildSwitcher(
            children: profile.children,
            selectedId: selected?.studentId,
            onSelect: selectChild,
            onAll: () => showAllChildren(profile.children),
          ),
          const SizedBox(height: AppSpacing.space6),
        ],

        if (selected == null && profile.hasMultipleChildren)
          for (final c in profile.children) ...[
            GestureDetector(
              key: Key('overview-${c.studentId}'),
              onTap: () => selectChild(c),
              // Touch convenience only: assistive tech gets the one
              // "View <name> only" button, not a second identical action.
              excludeFromSemantics: true,
              child: _TodayCard(
                child: c,
                state:
                    _overview[c.studentId] ??
                    const ScreenState<ChildDay>.loading(),
                onRetry: () => _loadOverview(profile.children),
                // The whole card stays tappable for touch; this is the same
                // choice as a real button for keyboard and screen readers.
                onOpen: () => selectChild(c),
                academy: widget.academy,
                now: widget.now,
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
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
              academy: widget.academy,
              now: widget.now,
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          // School attendance history: not for an Academy-only child (the
          // Academy summary above already lists their session attendance).
          // In an Academy institution it waits for a confirmed School record,
          // so it never flashes for an Academy-only child while loading or
          // after an error.
          if (_today.data?.school != null ||
              (_today.data == null && widget.academy == null))
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
    required this.onAll,
  });

  final List<GuardianChild> children;
  final String? selectedId;
  final ValueChanged<GuardianChild> onSelect;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    // Its own traversal group, so Tab walks the chips in order before
    // reaching the cards below.
    return FocusTraversalGroup(
      child: Semantics(
        container: true,
        label: 'Choose a child',
        child: _chips(),
      ),
    );
  }

  Widget _chips() {
    return Wrap(
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space3,
      children: [
        _ChildChip(
          key: const Key('all-children'),
          child: null,
          selected: selectedId == null,
          onTap: onAll,
        ),
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
    super.key,
    required this.child,
    required this.selected,
    required this.onTap,
  });

  /// Null renders the "All children" chip.
  final GuardianChild? child;
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

    // M5: keyboard-operable (Tab, Enter/Space) with the selected state
    // announced. The class goes into the spoken name, so two children with
    // similar names are still told apart.
    final c = child;
    final klass = c?.classLabel;
    return KeyboardTapTarget(
      label: c == null
          ? 'All children'
          : (klass == null ? c.fullName : '${c.fullName}, $klass'),
      selected: selected,
      onTap: onTap,
      borderRadius: AppRadius.full,
      // IntrinsicWidth keeps the chip at its label's width while the label is
      // centred inside the 48 px touch height.
      child: IntrinsicWidth(
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizing.buttonLg),
          alignment: Alignment.center,
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
            c?.fullName ?? 'All children',
            style: AppTypography.fieldLabel.copyWith(color: fg),
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
    this.onOpen,
    this.academy,
    this.now,
  });

  final GuardianChild child;
  final ScreenState<ChildDay> state;
  final VoidCallback onRetry;

  /// Overview only: shows this child on their own.
  final VoidCallback? onOpen;
  final AcademyRepository? academy;
  final DateTime Function()? now;

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
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    child.fullName,
                    style: AppTypography.cardHeading.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ),
              if (onOpen != null)
                AppButton(
                  key: Key('open-${child.studentId}'),
                  label: 'View',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  semanticsLabel: 'View ${child.fullName} only',
                  onPressed: onOpen,
                ),
            ],
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
          ScreenStateBuilder<ChildDay>(
            state: state,
            onRetry: onRetry,
            skeleton: const LoadingSkeletonLine(),
            emptyTitle: 'No record',
            emptyMessage: 'Nothing recorded for today yet.',
            data: (context, day) {
              final today = day.school;
              final academy = this.academy;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (today != null) ...[
                    _statusRow(context, today),
                    // T16: the rest of what this endpoint has always returned.
                    // T9 read only the attendance status because the screens
                    // that give the other fields meaning did not exist yet.
                    ChildProgressDetails(today: today),
                  ] else if (academy == null)
                    // Authorised, but no class enrollment and no Academy in
                    // this institution: a fact, not an error.
                    Text(
                      'Not enrolled in a class yet.',
                      style: AppTypography.bodyParentStudent.copyWith(
                        color: context.tokens.textSecondary,
                      ),
                    ),
                  if (academy != null)
                    AcademyChildSummary(
                      key: Key('academy-summary-${child.studentId}'),
                      repository: academy,
                      studentId: child.studentId,
                      hasSchoolRecord: today != null,
                      now: now,
                    ),
                ],
              );
            },
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
            'Today · ${formatBusinessDate(context, today.date)}',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
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

    return KeyboardTapTarget(
      label: 'View attendance history',
      onTap: onTap,
      borderRadius: AppRadius.lg,
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
                style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// One child's School snapshot for the landing card. [school] is null only
/// when the server said the child has no class enrollment (an authorised
/// answer, see [ParentRepository.loadToday]).
class ChildDay {
  const ChildDay(this.school);
  final ChildToday? school;
}

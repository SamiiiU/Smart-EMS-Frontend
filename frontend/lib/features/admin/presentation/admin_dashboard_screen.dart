import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/admin_repository.dart';
import '../domain/admin_models.dart';

/// The admin's landing screen.
///
/// Two rules carry this screen, and both are about what the admin is
/// actually doing: onboarding a school, not looking anything up.
///
/// - **D-15** — the section table sorts by COMPLETENESS, least complete
///   first. Alphabetical order scatters unfinished work through the list and
///   makes the next action invisible. The ordering rule itself lives on
///   [SectionCompleteness.completenessRank], stated there rather than here.
/// - **D-14** — the setup checklist appears only when NO records exist, not
///   when counters happen to read zero. See [AdminDashboard.isBrandNewSchool].
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.repository,
    this.onOpenStudents,
    this.onOpenImport,
    this.onOpenWizard,
    this.onOpenSetup,
    super.key,
  });

  final AdminRepository repository;
  final VoidCallback? onOpenStudents;
  final VoidCallback? onOpenImport;
  final VoidCallback? onOpenWizard;

  /// Opens the Setup hub (T13). Null in tests that do not wire it — the
  /// checklist step is then inert rather than leading nowhere (D-19).
  final VoidCallback? onOpenSetup;

  @override
  State<AdminDashboardScreen> createState() => AdminDashboardScreenState();
}

class AdminDashboardScreenState extends State<AdminDashboardScreen> {
  ScreenState<AdminDashboard> _state =
      const ScreenState<AdminDashboard>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() =>
        _state = ScreenState<AdminDashboard>.loading(previous: _state.data));
    try {
      final data = await widget.repository.loadDashboard();
      if (!mounted) return;
      setState(() => _state = ScreenState<AdminDashboard>.data(
            data,
            // A dashboard is a single record, never a collection — without
            // this the D-39 resolver would throw rather than guess.
            isEmpty: false,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = ScreenState<AdminDashboard>.failed(
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
      body: SafeArea(
        child: ScreenStateBuilder<AdminDashboard>(
          state: _state,
          onRetry: _load,
          emptyTitle: 'The dashboard could not be opened',
          emptyMessage: 'The school’s figures could not be read. Reopen this '
              'tab to try again — if it keeps happening, tell your system '
              'administrator.',
          data: (context, data) => _body(context, data),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AdminDashboard data) {
    final t = context.tokens;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Text(
          'Dashboard',
          style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
        ),
        // Title + one line of orientation, the same shape the Setup, Fees
        // and Academics hubs use. The dashboard was the only admin landing
        // surface without it, which made it read as the odd one out.
        const SizedBox(height: AppSpacing.space2),
        Text(
          data.isBrandNewSchool
              ? 'Nothing has been set up yet.'
              : 'Where the school needs attention.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),

        // D-14: the checklist replaces the dashboard ONLY for a genuinely
        // empty school. A school with records never sees it, however its
        // counters read.
        if (data.isBrandNewSchool) ...[
          _SetupChecklist(
            onOpenImport: widget.onOpenImport,
            onOpenWizard: widget.onOpenWizard,
            onOpenSetup: widget.onOpenSetup,
          ),
        ] else ...[
          // D-29: KPI stagger, 250ms, 60ms apart. The stagger is HONEST —
          // each figure comes from its own endpoint, so landing them all at
          // once would misrepresent how the screen actually fills.
          // Three EQUAL columns cram at 360px once the text scale is up —
          // "Students" wraps to two lines while "Staff" does not, and the
          // row goes ragged. Below the collapse breakpoint they stack, which
          // is the same rule AppDataTable already follows.
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _Kpi(label: 'Students', value: '${data.studentCount}'),
                _Kpi(label: 'Staff', value: '${data.staffCount}'),
                _Kpi(label: 'Sections', value: '${data.sections.length}'),
              ];
              final stacked =
                  constraints.maxWidth < AppSizing.tableCollapseBreakpoint;

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, card) in cards.indexed) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.space3),
                      MotionReveal.staggered(
                        index: i,
                        duration: AppMotion.kpiReveal,
                        child: card,
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (final (i, card) in cards.indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.space4),
                    Expanded(
                      child: MotionReveal.staggered(
                        index: i,
                        duration: AppMotion.kpiReveal,
                        child: card,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space8),
          // The list holds EVERY section, sorted least complete first — it
          // is not filtered to the unfinished ones. So when nothing is
          // unfinished, a heading saying "needing attention" is simply
          // untrue, and the sentence under it explains nothing. Both now
          // follow the data.
          Builder(
            builder: (context) {
              final needsAttention =
                  data.sections.where((s) => s.nextAction != null).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    needsAttention == 0
                        ? 'All sections'
                        : 'Sections needing attention',
                    style: AppTypography.sectionHeading
                        .copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    needsAttention == 0
                        ? 'Every section is set up.'
                        : '$needsAttention of ${data.sections.length} '
                            '${data.sections.length == 1 ? 'section is' : 'sections are'} '
                            'unfinished. Least complete first.',
                    style: AppTypography.bodyAdminMeta
                        .copyWith(color: t.textSecondary),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.space5),
          // D-29: section reveal, 200ms staggered. Capped at six steps by
          // AppMotion.staggerFor, so a long list does not keep arriving.
          for (final (i, section) in data.sections.indexed)
            MotionReveal.staggered(
              index: i,
              child: _SectionRow(section: section),
            ),
        ],
      ],
    );
  }
}

/// The brand-new-school path (D-14).
///
/// Ordered by DEPENDENCY, not importance: a student cannot be enrolled into
/// a section that does not exist, and staff cannot be assigned to teach a
/// class that has not been created. Presenting these in any other order
/// invites the admin to start with a step that cannot succeed yet.
class _SetupChecklist extends StatelessWidget {
  const _SetupChecklist({this.onOpenImport, this.onOpenWizard, this.onOpenSetup});

  final VoidCallback? onOpenImport;
  final VoidCallback? onOpenWizard;
  final VoidCallback? onOpenSetup;

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
            'Set up your school',
            style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Nothing has been created yet. These steps depend on each '
            'other, so they are listed in the order they have to happen.',
            style:
                AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space6),
          // Live as of T13 Batch A. It was inert for two tasks because no
          // screen could create a class or a section; both now exist under
          // Setup, so the step opens it. The checklist's TRIGGER is
          // unchanged (D-14) — it still appears only when no records exist.
          // Staggered in the order they have to happen, so the sequence is
          // legible as motion as well as as a list (D-29 section reveal).
          MotionReveal.staggered(
            index: 0,
            child: _ChecklistStep(
              number: 1,
              title: 'Set up years, classes and sections',
              detail: 'Students are enrolled INTO a section, so this comes '
                  'first. Subjects and the timetable are here too.',
              onTap: onOpenSetup,
            ),
          ),
          MotionReveal.staggered(
            index: 1,
            child: _ChecklistStep(
              number: 2,
              title: 'Import students',
              detail: 'Bulk-import your roster from a CSV file.',
              onTap: onOpenImport,
            ),
          ),
          MotionReveal.staggered(
            index: 2,
            child: _ChecklistStep(
              number: 3,
              title: 'Add staff',
              detail: 'Create teacher logins and link them to staff records.',
              onTap: onOpenWizard,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistStep extends StatelessWidget {
  const _ChecklistStep({
    required this.number,
    required this.title,
    required this.detail,
    this.onTap,
  });

  final int number;
  final String title;
  final String detail;

  /// Null where no screen exists to go to. A step with no destination stays
  /// inert rather than offering a tap that leads nowhere (D-19).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.space8,
            height: AppSpacing.space8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primarySubtle,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              '$number',
              style: AppTypography.overline.copyWith(color: t.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  detail,
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: t.textSecondary),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            label,
            style: AppTypography.overline.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});

  final SectionCompleteness section;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final action = section.nextAction;

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
      // Wrap rather than Row: the label and its status cannot share a line
      // at a large text scale on a narrow phone, and a Row overflows instead
      // of reflowing — the trap T8's roster row hit.
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            section.label,
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          Text(
            '${section.studentCount} '
            '${section.studentCount == 1 ? 'student' : 'students'}',
            style:
                AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          if (action != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: t.warningBg,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                action,
                style: AppTypography.overline
                    .copyWith(color: t.warningTextOnBg),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../admin/data/admin_repository.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';
import 'academic_years_screen.dart';
import 'setup_scaffold.dart';
import 'classes_screen.dart';
import 'sections_screen.dart';
import 'subjects_screen.dart';
import 'teaching_assignments_screen.dart';
import 'timetable_builder_screen.dart';

/// What every setup screen needs to know before it can write anything.
@immutable
class SetupContext {
  const SetupContext({
    required this.campusId,
    required this.years,
    required this.classes,
    required this.sections,
    required this.subjects,
  });

  final String? campusId;
  final List<AcademicYear> years;
  final List<SchoolClass> classes;
  final List<Section> sections;
  final List<Subject> subjects;

  /// The year sections and timetables are written against.
  ///
  /// The flagged one when there is one; otherwise the first year that
  /// exists, because work has to go somewhere and an admin mid-onboarding
  /// would rather be told which year than be blocked. Every screen that
  /// writes states the year it is using.
  AcademicYear? get workingYear {
    for (final y in years) {
      if (y.current) return y;
    }
    return years.isEmpty ? null : years.first;
  }

  bool get usingFallbackYear =>
      workingYear != null && !workingYear!.current;
}

/// The setup hub: the six steps of Batch A, in dependency order.
///
/// One tab rather than six, because the order is the point — a section
/// cannot exist before a class, and a timetable slot cannot exist before a
/// teaching assignment. Each row says what it needs and whether that is
/// there yet, so a blocked step explains itself instead of failing when
/// opened (the "Could not load this" problem).
class SetupHomeScreen extends StatefulWidget {
  const SetupHomeScreen({
    required this.setup,
    required this.admin,
    super.key,
  });

  final SetupRepository setup;

  /// Only for campuses and the staff list — the admin repository already
  /// owns both, and a second copy would be two places to fix.
  final AdminRepository admin;

  @override
  State<SetupHomeScreen> createState() => SetupHomeScreenState();
}

class SetupHomeScreenState extends State<SetupHomeScreen> {
  ScreenState<SetupContext> _state = const ScreenState<SetupContext>.loading();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() =>
        _state = ScreenState<SetupContext>.loading(previous: _state.data));
    try {
      final campuses = await widget.admin.loadCampusIds();
      final years = await widget.setup.loadYears();
      final classes = await widget.setup.loadClasses();
      final sections = await widget.setup.loadSections();
      final subjects = await widget.setup.loadSubjects();
      if (!mounted) return;
      setState(() => _state = ScreenState<SetupContext>.data(
            SetupContext(
              campusId: campuses.isEmpty ? null : campuses.first,
              years: years,
              classes: classes,
              sections: sections,
              subjects: subjects,
            ),
            // A context object is one record, never a collection.
            isEmpty: false,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<SetupContext>.failed(
            failure,
            cached: _state.data,
            connection: failure.unreachable
                ? NetworkStatus.offline
                : NetworkStatus.online,
          ));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    // Anything created in there changes what the next step can do.
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ScreenStateBuilder<SetupContext>(
          state: _state,
          onRetry: load,
          emptyTitle: 'Setup could not be opened',
          emptyMessage: 'The school’s years, classes and sections could not '
              'be read. Reopen this tab to try again — if it keeps '
              'happening, tell your system administrator.',
          data: (context, ctx) => _body(context, ctx),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SetupContext ctx) {
    final t = context.tokens;
    final year = ctx.workingYear;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Text(
          'School setup',
          style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Each step needs the one above it.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),

        if (ctx.campusId == null)
          const InlineAlert(
            tone: InlineAlertTone.danger,
            message: 'This school has no campus, so nothing can be created '
                'yet. A campus is set up when the school is created — ask '
                'your system administrator.',
          )
        else if (year == null)
          const InlineAlert(
            tone: InlineAlertTone.info,
            message: 'Start with an academic year. Sections, timetables and '
                'enrolments all belong to one.',
          )
        else if (ctx.usingFallbackYear)
          InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'No year is marked as current, so “${year.name}” is '
                'being used. The current year can only be changed by your '
                'system administrator.',
          ),
        const SizedBox(height: AppSpacing.space6),

        StepRow(
          number: 1,
          title: 'Academic years',
          detail: year == null
              ? 'None yet.'
              : 'Working year: ${year.name}'
                  '${year.current ? ' (current)' : ''}',
          count: ctx.years.length,
          onTap: ctx.campusId == null
              ? null
              : () => _open(AcademicYearsScreen(
                    repository: widget.setup,
                    campusId: ctx.campusId!,
                  )),
        ),
        StepRow(
          number: 2,
          title: 'Classes',
          detail: 'Grades or class levels, in teaching order.',
          count: ctx.classes.length,
          onTap: ctx.campusId == null
              ? null
              : () => _open(ClassesScreen(
                    repository: widget.setup,
                    campusId: ctx.campusId!,
                  )),
          blockedReason: ctx.campusId == null ? 'Needs a campus' : null,
        ),
        StepRow(
          number: 3,
          title: 'Sections',
          detail: 'Each class is divided into sections for one year.',
          count: ctx.sections.length,
          onTap: (ctx.classes.isEmpty || year == null)
              ? null
              : () => _open(SectionsScreen(
                    repository: widget.setup,
                    admin: widget.admin,
                    classes: ctx.classes,
                    year: year,
                  )),
          blockedReason: year == null
              ? 'Create an academic year first'
              : ctx.classes.isEmpty
                  ? 'Create a class first'
                  : null,
        ),
        StepRow(
          number: 4,
          title: 'Subjects',
          detail: 'Taught across the school.',
          count: ctx.subjects.length,
          onTap: () => _open(SubjectsScreen(repository: widget.setup)),
        ),
        StepRow(
          number: 5,
          title: 'Who teaches what',
          detail: 'A teacher for each subject, in each section.',
          onTap: (ctx.sections.isEmpty ||
                  ctx.subjects.isEmpty ||
                  year == null)
              ? null
              : () => _open(TeachingAssignmentsScreen(
                    repository: widget.setup,
                    admin: widget.admin,
                    classes: ctx.classes,
                    sections: ctx.sections,
                    subjects: ctx.subjects,
                    year: year,
                  )),
          blockedReason: year == null
              ? 'Create an academic year first'
              : ctx.sections.isEmpty
                  ? 'Create a section first'
                  : ctx.subjects.isEmpty
                      ? 'Create a subject first'
                      : null,
        ),
        StepRow(
          number: 6,
          title: 'Timetable',
          detail: 'Periods for the school, then each section’s week.',
          onTap: (ctx.campusId == null || ctx.sections.isEmpty || year == null)
              ? null
              : () => _open(TimetableBuilderScreen(
                    repository: widget.setup,
                    admin: widget.admin,
                    campusId: ctx.campusId!,
                    classes: ctx.classes,
                    sections: ctx.sections,
                    subjects: ctx.subjects,
                    year: year,
                  )),
          blockedReason: year == null
              ? 'Create an academic year first'
              : ctx.sections.isEmpty
                  ? 'Create a section first'
                  : null,
        ),
      ],
    );
  }
}


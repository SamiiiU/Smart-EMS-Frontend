import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../admin/data/admin_repository.dart';
import '../../setup/data/setup_repository.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import 'exam_setup_screen.dart';
import 'remarks_screen.dart';
import 'syllabus_screen.dart';
import 'unavailable_screens.dart';

/// What the academic screens need before they can do anything.
@immutable
class AcademicsContext {
  const AcademicsContext({
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

  /// The year exams and syllabus are written against.
  ///
  /// Chosen here and passed explicitly, as everywhere else — the backend's
  /// `current` flag points at an expired year. `POST /api/exams` REQUIRES
  /// the year rather than resolving one, which is why exam creation is not
  /// blocked the way a server-resolved write would have to be.
  AcademicYear? get workingYear {
    for (final y in years) {
      if (y.current) return y;
    }
    return years.isEmpty ? null : years.first;
  }

  bool get usingFallbackYear => workingYear != null && !workingYear!.current;
}

/// The academics hub: exams, marks, results and the syllabus.
///
/// Two of its steps have no backend at all and say so rather than being
/// hidden — see [GradeSchemesScreen] and [SubjectResourcesScreen].
class AcademicsHomeScreen extends StatefulWidget {
  const AcademicsHomeScreen({
    required this.academics,
    required this.setup,
    required this.admin,
    super.key,
  });

  final AcademicsRepository academics;
  final SetupRepository setup;
  final AdminRepository admin;

  @override
  State<AcademicsHomeScreen> createState() => AcademicsHomeScreenState();
}

class AcademicsHomeScreenState extends State<AcademicsHomeScreen> {
  ScreenState<AcademicsContext> _state =
      const ScreenState<AcademicsContext>.loading();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() =>
        _state = ScreenState<AcademicsContext>.loading(previous: _state.data));
    try {
      final campuses = await widget.admin.loadCampusIds();
      final years = await widget.setup.loadYears();
      final classes = await widget.setup.loadClasses();
      final sections = await widget.setup.loadSections();
      final subjects = await widget.setup.loadSubjects();
      if (!mounted) return;
      setState(() => _state = ScreenState<AcademicsContext>.data(
            AcademicsContext(
              campusId: campuses.isEmpty ? null : campuses.first,
              years: years,
              classes: classes,
              sections: sections,
              subjects: subjects,
            ),
            isEmpty: false,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<AcademicsContext>.failed(
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
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ScreenStateBuilder<AcademicsContext>(
          state: _state,
          onRetry: load,
          emptyTitle: 'Academics could not be opened',
          emptyMessage: 'The year, classes and subjects could not be read. '
              'Reopen this tab to try again — if it keeps happening, tell '
              'your system administrator.',
          data: _body,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AcademicsContext ctx) {
    final t = context.tokens;
    final year = ctx.workingYear;
    final noSections = ctx.sections.isEmpty;
    final noSubjects = ctx.subjects.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Text(
          'Academics',
          style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Exams and marks, and what has been taught so far.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),

        if (ctx.campusId == null)
          const InlineAlert(
            tone: InlineAlertTone.danger,
            message: 'This school has no campus, so no exam can be created. '
                'Ask your system administrator.',
          )
        else if (year == null)
          const InlineAlert(
            tone: InlineAlertTone.info,
            message: 'Exams belong to an academic year. Create one under '
                'Setup first.',
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
          title: 'Grade scheme',
          detail: 'How percentages become grades.',
          onTap: () => _open(const GradeSchemesScreen()),
        ),
        StepRow(
          number: 2,
          title: 'Exams',
          detail: 'Create an exam, add its papers, enter marks, publish.',
          onTap: (year == null || ctx.campusId == null || noSections ||
                  noSubjects)
              ? null
              : () => _open(ExamSetupScreen(
                    repository: widget.academics,
                                  year: year,
                    campusId: ctx.campusId!,
                    sections: ctx.sections,
                    classes: ctx.classes,
                    subjects: ctx.subjects,
                  )),
          blockedReason: year == null
              ? 'Create an academic year first'
              : noSections
                  ? 'Create a section first'
                  : noSubjects
                      ? 'Create a subject first'
                      : null,
        ),
        StepRow(
          number: 3,
          title: 'Remarks',
          detail: 'Notes about a student, and who can see them.',
          onTap: noSections
              ? null
              : () => _open(RemarksScreen(
                    repository: widget.academics,
                                  sectionId: ctx.sections.first.id,
                    sectionName: _sectionLabel(ctx, ctx.sections.first),
                  )),
          blockedReason: noSections ? 'Create a section first' : null,
        ),
        StepRow(
          number: 4,
          title: 'Syllabus',
          detail: 'Chapters and topics, and how much has been covered.',
          onTap: (year == null || noSections || noSubjects)
              ? null
              : () => _open(SyllabusScreen(
                    repository: widget.academics,
                    year: year,
                    classes: ctx.classes,
                    sections: ctx.sections,
                    subjects: ctx.subjects,
                  )),
          blockedReason: year == null
              ? 'Create an academic year first'
              : noSections
                  ? 'Create a section first'
                  : noSubjects
                      ? 'Create a subject first'
                      : null,
        ),
        StepRow(
          number: 5,
          title: 'Subject resources',
          detail: 'Books, notes and links for a subject.',
          onTap: () => _open(const SubjectResourcesScreen()),
        ),
      ],
    );
  }

  String _sectionLabel(AcademicsContext ctx, Section s) {
    for (final c in ctx.classes) {
      if (c.id == s.classId) return '${c.name} ${s.name}';
    }
    return s.name;
  }
}

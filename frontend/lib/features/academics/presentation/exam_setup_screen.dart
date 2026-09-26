import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';
import '../domain/marks.dart';
import 'exam_papers_screen.dart';

/// Screen 2: exams.
///
/// The academic year is passed EXPLICITLY — `POST /api/exams` requires it
/// and does not resolve one, which is exactly why exam creation is not
/// blocked by the current-year bug the way a server-resolved action would
/// be. The screen names the year it is writing into.
class ExamSetupScreen extends StatefulWidget {
  const ExamSetupScreen({
    required this.repository,
    required this.year,
    required this.campusId,
    required this.sections,
    required this.classes,
    required this.subjects,
    super.key,
  });

  final AcademicsRepository repository;
  final AcademicYear year;
  final String campusId;
  final List<Section> sections;
  final List<SchoolClass> classes;
  final List<Subject> subjects;

  @override
  State<ExamSetupScreen> createState() => ExamSetupScreenState();
}

class ExamSetupScreenState extends State<ExamSetupScreen> {
  ScreenState<List<Exam>> _state = const ScreenState<List<Exam>>.loading();

  String _name = '';
  ExamTerm? _term;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() =>
        _state = ScreenState<List<Exam>>.loading(previous: _state.data));
    try {
      final exams =
          await widget.repository.loadExams(academicYearId: widget.year.id);
      if (!mounted) return;
      setState(() => _state = ScreenState<List<Exam>>.data(exams));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Exam>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<String?> _create() async {
    try {
      await widget.repository.createExam(
        campusId: widget.campusId,
        academicYearId: widget.year.id,
        name: _name.trim(),
        term: _term,
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _term = null;
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The exam could not be created.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Exams',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message: 'Exams are created in “${widget.year.name}”.',
      ),
      children: [
        CreatePanel(
          addLabel: 'Add an exam',
          canSubmit: _name.trim().isNotEmpty,
          onSubmit: _create,
          confirmNote: 'An exam cannot be renamed or removed afterwards — '
              'this system has no edit or delete for one.',
          fields: [
            SetupField(
              label: 'Name',
              value: _name,
              placeholder: 'e.g. First Term 2026',
              onChanged: (v) => setState(() => _name = v),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Term (optional)',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  // Only the six values the backend accepts. An unlisted
                  // term answers a 400 that does not even name the field.
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final term in ExamTerm.values)
                        PickerChip(
                          label: term.label,
                          selected: _term == term,
                          onTap: () => setState(
                            () => _term = _term == term ? null : term,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Exam>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No exams yet',
            emptyMessage: 'An exam holds one paper per subject per section. '
                'Marks are entered against those papers.',
            emptyIcon: Icons.assignment_outlined,
            data: (context, exams) => ListView(
              children: [
                for (final exam in exams)
                  _ExamRow(
                    exam: exam,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExamPapersScreen(
                            repository: widget.repository,
                                                  exam: exam,
                            sections: widget.sections,
                            classes: widget.classes,
                            subjects: widget.subjects,
                          ),
                        ),
                      );
                      await _load();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({required this.exam, required this.onTap});

  final Exam exam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      label: '${exam.name}, '
          '${exam.status == ExamStatus.published ? 'published' : 'not published'}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.space3),
            padding: const EdgeInsets.all(AppSpacing.space5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: t.border),
            ),
            child: Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  exam.name,
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
                if (exam.term != null)
                  Text(
                    exam.termLabel,
                    style: AppTypography.bodyAdminMeta
                        .copyWith(color: t.textSecondary),
                  ),
                StatusPill(status: exam.status.pill, size: StatusPillSize.sm),
                if (exam.marksLocked)
                  Text(
                    'Marks locked',
                    style: AppTypography.bodyAdminMeta
                        .copyWith(color: t.warningTextOnBg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Parses a marks field, used by the paper form. Exposed for its test.
Marks? parseMarksField(String raw) {
  final value = Marks.tryParse(raw);
  if (value == null || value.hundredths <= 0) return null;
  return value;
}

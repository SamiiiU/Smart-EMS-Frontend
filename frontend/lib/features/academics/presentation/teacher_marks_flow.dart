import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/keyboard_tap_target.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';
import 'marks_entry_screen.dart';

/// OBS-06 (owner-approved route) + D-13: the teacher's way into Marks Entry.
///
/// Exams whose marks are still editable → this teacher's papers in that exam
/// (`GET /api/exams/{id}/subjects` returns ONLY papers the teacher may enter
/// marks for) → the existing Marks Entry screen, which keeps every rule
/// (bulk POST, over-maximum guard, assignment check on the server).
/// Against a backend without D-13 the papers call fails and the screen says
/// so; nothing is guessed.
class TeacherMarksFlow extends StatefulWidget {
  const TeacherMarksFlow({required this.repository, super.key});

  final AcademicsRepository repository;

  @override
  State<TeacherMarksFlow> createState() => TeacherMarksFlowState();
}

class TeacherMarksFlowState extends State<TeacherMarksFlow> {
  ScreenState<List<Exam>> _state = const ScreenState<List<Exam>>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
      () => _state = ScreenState<List<Exam>>.loading(previous: _state.data),
    );
    try {
      final exams = await widget.repository.loadExamsForMarking();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<Exam>>.data(exams));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ScreenState<List<Exam>>.failed(
          e is LoadFailure ? e : const LoadFailure(),
          cached: _state.data,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ScreenStateBuilder<List<Exam>>(
          state: _state,
          onRetry: _load,
          emptyTitle: 'No exams open for marks',
          emptyMessage:
              'Marks can be entered while an exam is in draft, marking or '
              'moderation. None is open right now.',
          emptyIcon: Icons.edit_note_outlined,
          data: (context, exams) => ListView(
            padding: const EdgeInsets.all(AppSpacing.space6),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Marks',
                  style: AppTypography.screenTitle.copyWith(
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              for (final e in exams)
                _Row(
                  title: e.name,
                  detail: e.status.label,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _TeacherPapersScreen(
                        repository: widget.repository,
                        exam: e,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherPapersScreen extends StatefulWidget {
  const _TeacherPapersScreen({required this.repository, required this.exam});

  final AcademicsRepository repository;
  final Exam exam;

  @override
  State<_TeacherPapersScreen> createState() => _TeacherPapersScreenState();
}

class _TeacherPapersScreenState extends State<_TeacherPapersScreen> {
  ScreenState<List<ExamPaper>> _state =
      const ScreenState<List<ExamPaper>>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
      () =>
          _state = ScreenState<List<ExamPaper>>.loading(previous: _state.data),
    );
    try {
      final papers = await widget.repository.loadPapers(widget.exam.id);
      if (!mounted) return;
      setState(() => _state = ScreenState<List<ExamPaper>>.data(papers));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ScreenState<List<ExamPaper>>.failed(
          e is LoadFailure
              ? e
              : const LoadFailure(
                  message: 'Your papers for this exam could not be loaded.',
                ),
          cached: _state.data,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(title: Text(widget.exam.name)),
      body: SafeArea(
        child: ScreenStateBuilder<List<ExamPaper>>(
          state: _state,
          onRetry: _load,
          emptyTitle: 'No papers for you in this exam',
          emptyMessage:
              'Papers appear here for the sections and subjects you are '
              'assigned to teach.',
          emptyIcon: Icons.assignment_outlined,
          data: (context, papers) => ListView(
            padding: const EdgeInsets.all(AppSpacing.space6),
            children: [
              for (final p in papers)
                _Row(
                  title: p.subjectName.isEmpty ? 'Paper' : p.subjectName,
                  detail: '${p.sectionName} · out of ${p.maxMarks.format()}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MarksEntryScreen(
                        repository: widget.repository,
                        paper: p,
                        examName: widget.exam.name,
                        marksLocked: !widget.exam.status.marksEditable,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.detail, required this.onTap});

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: KeyboardTapTarget(
        label: '$title, $detail',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.cardHeading.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      detail,
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

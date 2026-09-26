import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';
import '../domain/marks.dart';
import 'marks_entry_screen.dart';
import 'results_screen.dart';

/// An exam's papers, and everything that hangs off them.
///
/// 🔴 **This screen cannot list the papers that already exist.**
/// `GET /api/exams/{id}/subjects` is 405, and re-creating a paper answers
/// 409 *without* returning the existing id — so once this screen is closed,
/// a paper's id is gone for good and marks can no longer be entered against
/// it.
///
/// That is the single sharpest limitation in this batch, so it is stated at
/// the top of the screen rather than discovered by a teacher who has walked
/// away and come back. Papers created in this session stay listed below,
/// with "Enter marks" on each, and the warning says plainly what happens if
/// you leave. Open items 26 and 27.
class ExamPapersScreen extends StatefulWidget {
  const ExamPapersScreen({
    required this.repository,
    required this.exam,
    required this.sections,
    required this.classes,
    required this.subjects,
    super.key,
  });

  final AcademicsRepository repository;
  final Exam exam;
  final List<Section> sections;
  final List<SchoolClass> classes;
  final List<Subject> subjects;

  @override
  State<ExamPapersScreen> createState() => ExamPapersScreenState();
}

class ExamPapersScreenState extends State<ExamPapersScreen> {
  /// Papers created in THIS session. The backend cannot give them back.
  final List<ExamPaper> _papers = [];

  String? _sectionId;
  String? _subjectId;
  String _maxMarks = '100';
  String _passingMarks = '40';

  bool _publishing = false;
  String? _error;
  PublishResult? _published;
  late ExamStatus _status = widget.exam.status;

  @override
  void initState() {
    super.initState();
    _sectionId = widget.sections.isEmpty ? null : widget.sections.first.id;
    _subjectId = widget.subjects.isEmpty ? null : widget.subjects.first.id;
  }

  String _sectionLabel(String id) {
    for (final s in widget.sections) {
      if (s.id == id) {
        for (final c in widget.classes) {
          if (c.id == s.classId) return '${c.name} ${s.name}';
        }
        return s.name;
      }
    }
    return 'Section';
  }

  String _subjectLabel(String id) {
    for (final s in widget.subjects) {
      if (s.id == id) return s.name;
    }
    return 'Subject';
  }

  bool get _canAddPaper =>
      _sectionId != null &&
      _subjectId != null &&
      Marks.tryParse(_maxMarks.trim()) != null &&
      Marks.tryParse(_passingMarks.trim()) != null &&
      !_status.isPublished;

  Future<String?> _addPaper() async {
    final max = Marks.tryParse(_maxMarks.trim());
    final pass = Marks.tryParse(_passingMarks.trim());
    if (max == null || pass == null) {
      return 'Marks are numbers with at most two decimals.';
    }
    if (max.hundredths <= 0) return 'Maximum marks must be above zero.';
    if (pass.compareTo(max) > 0) {
      return 'The passing mark cannot be higher than the maximum.';
    }

    try {
      final paper = await widget.repository.createPaper(
        examId: widget.exam.id,
        sectionId: _sectionId!,
        subjectId: _subjectId!,
        maxMarks: max,
        passingMarks: pass,
        subjectName: _subjectLabel(_subjectId!),
        sectionName: _sectionLabel(_sectionId!),
      );
      if (!mounted) return null;
      setState(() => _papers.add(paper));
      return null;
    } on LoadFailure catch (f) {
      // 409 here means this section/subject pair already has a paper — and
      // the response does NOT carry its id, so it cannot be recovered.
      final message = f.message ?? '';
      if (message.contains('Conflicts with existing data')) {
        return 'This section already has a paper for that subject in this '
            'exam. It cannot be opened again — this system has no way to '
            'look a paper up once it has been created.';
      }
      return message.isEmpty ? 'The paper could not be created.' : message;
    }
  }

  Future<void> _publish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish this exam?'),
        content: const Text(
          'Results and report cards become available to parents.\n\n'
          'This cannot be undone, and the marks are locked permanently — '
          'after publishing, no mark in this exam can be corrected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _publishing = true;
      _error = null;
    });
    final outcome = await widget.repository.publish(widget.exam.id);
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _error = outcome.error;
      _published = outcome.result;
      if (outcome.result != null) _status = ExamStatus.published;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: widget.exam.name,
      note: _status.isPublished
          ? const InlineAlert(
              tone: InlineAlertTone.warning,
              message: 'This exam is published. Its marks are locked and no '
                  'further papers can be added.',
            )
          : const InlineAlert(
              tone: InlineAlertTone.warning,
              message: 'Enter each paper’s marks before leaving this screen. '
                  'This system cannot list papers back, so once you go, a '
                  'paper cannot be reopened and marks can no longer be '
                  'entered against it.',
            ),
      children: [
        if (!_status.isPublished)
          CreatePanel(
            addLabel: 'Add a paper',
            canSubmit: _canAddPaper,
            onSubmit: _addPaper,
            confirmNote: 'A paper cannot be edited or removed afterwards, '
                'and cannot be found again once you leave this screen.',
            fields: [
              _Picker(
                label: 'Section',
                children: [
                  for (final s in widget.sections)
                    PickerChip(
                      label: _sectionLabel(s.id),
                      selected: _sectionId == s.id,
                      onTap: () => setState(() => _sectionId = s.id),
                    ),
                ],
              ),
              _Picker(
                label: 'Subject',
                children: [
                  for (final s in widget.subjects)
                    PickerChip(
                      label: s.name,
                      selected: _subjectId == s.id,
                      onTap: () => setState(() => _subjectId = s.id),
                    ),
                ],
              ),
              SetupField(
                label: 'Out of',
                value: _maxMarks,
                onChanged: (v) => setState(() => _maxMarks = v),
              ),
              SetupField(
                label: 'Passing mark',
                value: _passingMarks,
                onChanged: (v) => setState(() => _passingMarks = v),
              ),
            ],
          ),

        Text(
          'Papers added now',
          style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          _papers.isEmpty
              ? 'Nothing yet. Papers you add appear here with a link to '
                  'enter their marks.'
              : 'These are the papers created in this session — the only '
                  'ones whose marks can still be entered.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space4),

        for (final paper in _papers)
          _PaperRow(
            paper: paper,
            locked: _status.isPublished,
            onEnterMarks: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MarksEntryScreen(
                  repository: widget.repository,
                              paper: paper,
                  examName: widget.exam.name,
                  marksLocked: _status.isPublished,
                ),
              ),
            ),
            onResults: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ResultsScreen(
                  repository: widget.repository,
                  exam: widget.exam,
                  sectionId: paper.sectionId,
                  sectionName: paper.sectionName,
                ),
              ),
            ),
          ),

        const SizedBox(height: AppSpacing.space6),

        if (_error != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          const SizedBox(height: AppSpacing.space4),
        ],
        if (_published != null) ...[
          InlineAlert(
            tone: InlineAlertTone.success,
            message: '${_published!.resultsPublished} '
                '${_published!.resultsPublished == 1 ? 'result' : 'results'} '
                'published and ${_published!.reportCardsGenerated} '
                '${_published!.reportCardsGenerated == 1 ? 'report card' : 'report cards'} '
                'generated.',
          ),
          const SizedBox(height: AppSpacing.space4),
        ],

        if (!_status.isPublished)
          AppButton(
            label: _publishing ? 'Publishing…' : 'Publish results',
            fullWidth: true,
            onPressed: _publishing ? null : _publish,
          ),
      ],
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _PaperRow extends StatelessWidget {
  const _PaperRow({
    required this.paper,
    required this.locked,
    required this.onEnterMarks,
    required this.onResults,
  });

  final ExamPaper paper;
  final bool locked;
  final VoidCallback onEnterMarks;
  final VoidCallback onResults;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${paper.subjectName} · ${paper.sectionName}',
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            'Out of ${paper.maxMarks.format()} · '
            'pass ${paper.passingMarks.format()}',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space4),
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              AppButton(
                label: locked ? 'View marks' : 'Enter marks',
                onPressed: onEnterMarks,
              ),
              AppButton(
                label: 'Results',
                variant: AppButtonVariant.secondary,
                onPressed: onResults,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on ExamStatus {
  bool get isPublished => this == ExamStatus.published;
}

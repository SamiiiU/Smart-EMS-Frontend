import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

/// Screen 7: syllabus coverage.
///
/// Chapters and topics per subject and class; a teacher marks topics covered
/// for their section.
///
/// 🔴 **Progress is the server's, not ours.** The T15 brief assumed the
/// backend does not provide it and that computing `covered ÷ total`
/// client-side was the one correct place to do so. It does provide it —
/// `GET /api/syllabus/progress` returns the percentage, the covered and
/// total counts, and a per-chapter breakdown — so the same rule as marks
/// and money applies here too: render it, never derive it.
///
/// Re-marking a topic UPDATES rather than conflicting (verified live), so a
/// mis-tap is simply corrected by tapping the right one.
class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({
    required this.repository,
    required this.year,
    required this.classes,
    required this.sections,
    required this.subjects,
    super.key,
  });

  final AcademicsRepository repository;
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Section> sections;
  final List<Subject> subjects;

  @override
  State<SyllabusScreen> createState() => SyllabusScreenState();
}

class SyllabusScreenState extends State<SyllabusScreen> {
  ScreenState<List<Chapter>> _state =
      const ScreenState<List<Chapter>>.loading();
  SyllabusProgress? _progress;

  String? _subjectId;
  String? _sectionId;

  String _chapterName = '';
  String? _topicChapterId;
  String _topicName = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjects.isEmpty ? null : widget.subjects.first.id;
    _sectionId = widget.sections.isEmpty ? null : widget.sections.first.id;
    load();
  }

  Section? get _section {
    for (final s in widget.sections) {
      if (s.id == _sectionId) return s;
    }
    return null;
  }

  String? get _classId => _section?.classId;

  String _sectionLabel(Section s) {
    for (final c in widget.classes) {
      if (c.id == s.classId) return '${c.name} ${s.name}';
    }
    return s.name;
  }

  Future<void> load() async {
    final subjectId = _subjectId;
    final classId = _classId;
    final sectionId = _sectionId;
    if (subjectId == null || classId == null || sectionId == null) {
      setState(() => _state = const ScreenState<List<Chapter>>.data([]));
      return;
    }

    setState(() =>
        _state = ScreenState<List<Chapter>>.loading(previous: _state.data));
    try {
      final chapters = await widget.repository.loadChapters(
        subjectId: subjectId,
        classId: classId,
        academicYearId: widget.year.id,
      );
      final progress = await widget.repository.loadProgress(
        subjectId: subjectId,
        classId: classId,
        sectionId: sectionId,
        academicYearId: widget.year.id,
      );
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _state = ScreenState<List<Chapter>>.data(chapters);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Chapter>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<String?> _addChapter() async {
    final subjectId = _subjectId;
    final classId = _classId;
    if (subjectId == null || classId == null) {
      return 'Choose a subject and a section first.';
    }
    try {
      await widget.repository.createChapter(
        subjectId: subjectId,
        classId: classId,
        academicYearId: widget.year.id,
        name: _chapterName.trim(),
        sortOrder: (_state.data?.length ?? 0) + 1,
      );
      if (!mounted) return null;
      setState(() => _chapterName = '');
      await load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The chapter could not be added.';
    }
  }

  Future<String?> _addTopic() async {
    final chapterId = _topicChapterId;
    if (chapterId == null) return 'Choose a chapter first.';
    final chapter =
        (_state.data ?? const <Chapter>[]).where((c) => c.id == chapterId);
    try {
      await widget.repository.createTopic(
        chapterId: chapterId,
        name: _topicName.trim(),
        sortOrder: chapter.isEmpty ? 1 : chapter.first.topics.length + 1,
      );
      if (!mounted) return null;
      setState(() => _topicName = '');
      await load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The topic could not be added.';
    }
  }

  Future<void> _mark(Topic topic, CoverageStatus status) async {
    final sectionId = _sectionId;
    if (sectionId == null) return;
    final error = await widget.repository.markCoverage(
      topicId: topic.id,
      sectionId: sectionId,
      status: status,
      coveredOn: DateTime.now().toIso8601String().split('T').first,
    );
    if (!mounted) return;
    setState(() => _error = error);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final progress = _progress;
    final chapters = _state.data ?? const <Chapter>[];

    return SetupScaffold(
      title: 'Syllabus',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message: 'Chapters belong to a subject and class in '
            '“${widget.year.name}”. Coverage is recorded per section.',
      ),
      children: [
        _Picker(
          label: 'Subject',
          children: [
            for (final s in widget.subjects)
              PickerChip(
                label: s.name,
                selected: _subjectId == s.id,
                onTap: () {
                  setState(() => _subjectId = s.id);
                  load();
                },
              ),
          ],
        ),
        _Picker(
          label: 'Section',
          children: [
            for (final s in widget.sections)
              PickerChip(
                label: _sectionLabel(s),
                selected: _sectionId == s.id,
                onTap: () {
                  setState(() => _sectionId = s.id);
                  load();
                },
              ),
          ],
        ),

        if (progress != null && progress.totalTopics > 0) ...[
          const SizedBox(height: AppSpacing.space4),
          Container(
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
                  // The server's percentage, rendered. Not covered ÷ total
                  // computed here — that would be a second source of truth.
                  '${progress.percentage.formatPercent()} covered',
                  style: AppTypography.sectionHeading
                      .copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  '${progress.coveredTopics} of ${progress.totalTopics} '
                  'topics · ${progress.coveredChapters} of '
                  '${progress.totalChapters} chapters',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space4),
                // The only place a percentage becomes a double, and it is
                // for the BAR'S WIDTH, never for a number anyone reads —
                // the figure above is rendered from the exact value. A
                // pixel of rounding in a bar is not a defect; a rounded
                // percentage on a report is.
                ProgressBar(
                  percent: progress.percentage.hundredths / 100,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space5),
        ],

        if (_error != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          const SizedBox(height: AppSpacing.space4),
        ],

        CreatePanel(
          addLabel: 'Add a chapter',
          canSubmit: _chapterName.trim().isNotEmpty && _classId != null,
          onSubmit: _addChapter,
          fields: [
            SetupField(
              label: 'Chapter name',
              value: _chapterName,
              placeholder: 'e.g. Algebra',
              onChanged: (v) => setState(() => _chapterName = v),
            ),
          ],
        ),

        if (chapters.isNotEmpty)
          CreatePanel(
            addLabel: 'Add a topic',
            canSubmit: _topicName.trim().isNotEmpty && _topicChapterId != null,
            onSubmit: _addTopic,
            fields: [
              _Picker(
                label: 'Chapter',
                children: [
                  for (final c in chapters)
                    PickerChip(
                      label: c.name,
                      selected: _topicChapterId == c.id,
                      onTap: () => setState(() => _topicChapterId = c.id),
                    ),
                ],
              ),
              SetupField(
                label: 'Topic name',
                value: _topicName,
                placeholder: 'e.g. Quadratic equations',
                onChanged: (v) => setState(() => _topicName = v),
              ),
            ],
          ),

        SizedBox(
          height: MediaQuery.sizeOf(context).height / 2,
          child: ScreenStateBuilder<List<Chapter>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'No chapters yet',
            emptyMessage: 'Add the chapters for this subject, then the '
                'topics inside them. Teachers mark topics as they cover '
                'them.',
            emptyIcon: Icons.menu_book_outlined,
            data: (context, rows) => ListView(
              children: [
                for (final chapter in rows)
                  _ChapterBlock(
                    chapter: chapter,
                    progress: _progress,
                    onMark: _mark,
                  ),
              ],
            ),
          ),
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

class _ChapterBlock extends StatelessWidget {
  const _ChapterBlock({
    required this.chapter,
    required this.progress,
    required this.onMark,
  });

  final Chapter chapter;
  final SyllabusProgress? progress;
  final void Function(Topic, CoverageStatus) onMark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // The server's own per-chapter line, matched by name — the progress
    // payload carries no chapter id.
    ChapterProgress? chapterProgress;
    for (final c in progress?.chapters ?? const <ChapterProgress>[]) {
      if (c.name == chapter.name) chapterProgress = c;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space4),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                chapter.name,
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              if (chapterProgress != null)
                Text(
                  '${chapterProgress.covered} of ${chapterProgress.topics} '
                  'covered',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          if (chapter.topics.isEmpty)
            Text(
              'No topics in this chapter yet.',
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
            )
          else
            for (final topic in chapter.topics)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      topic.name,
                      style: AppTypography.bodyAdminMeta
                          .copyWith(color: t.textPrimary),
                    ),
                    for (final status in CoverageStatus.values)
                      PickerChip(
                        label: status.label,
                        selected: false,
                        onTap: () => onMark(topic, status),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

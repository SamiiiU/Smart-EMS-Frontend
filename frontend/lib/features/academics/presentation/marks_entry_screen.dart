import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../attendance/domain/attendance_models.dart' show RosterStudent;
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';
import '../domain/marks.dart';

/// Marks entry — the high-frequency screen of this batch.
///
/// This gets **attendance-marking treatment, not form treatment**. A teacher
/// enters marks for forty students in one sitting, so the design goals are
/// the same as the roll call:
///
///  - one interaction per student — type the number, move on;
///  - **keyboard-first on desktop**: `Tab` (and Enter) moves to the next
///    student and nothing submits the form, because a stray Enter halfway
///    down a class is the worst possible outcome;
///  - **absent is a toggle**, not a dropdown — it is a single tap, and it
///    clears the number so the two can never disagree;
///  - **validation runs as they type**, shown on the offending row. Finding
///    out at the end which of forty rows was over the maximum is the whole
///    problem;
///  - the **summary stays visible without scrolling**, so "how many left"
///    never costs a scroll to the bottom;
///  - 56px rows, the whole row is the target.
///
/// 🔴 **Marks cannot be read back.** There is no marks GET, so this screen
/// always starts empty even if marks were entered before — it cannot show
/// what is already saved. Stated on screen rather than letting a teacher
/// think the class is unmarked. Open item 26.
class MarksEntryScreen extends StatefulWidget {
  const MarksEntryScreen({
    required this.repository,
    required this.paper,
    required this.examName,
    this.marksLocked = false,
    super.key,
  });

  final AcademicsRepository repository;

  final ExamPaper paper;
  final String examName;

  /// True once the exam is published. Marks are then locked server-side,
  /// permanently, and there is no unpublish.
  final bool marksLocked;

  @override
  State<MarksEntryScreen> createState() => MarksEntryScreenState();
}

class MarksEntryScreenState extends State<MarksEntryScreen> {
  ScreenState<List<RosterStudent>> _roster =
      const ScreenState<List<RosterStudent>>.loading();

  /// studentId → entry.
  final Map<String, MarkEntry> _entries = {};
  final Map<String, FocusNode> _focus = {};
  final Map<String, TextEditingController> _controllers = {};

  bool _saving = false;
  String? _error;
  MarksSaveResult? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _roster =
        ScreenState<List<RosterStudent>>.loading(previous: _roster.data));
    try {
      final students =
          await widget.repository.loadRoster(widget.paper.sectionId);
      if (!mounted) return;
      setState(() {
        for (final s in students) {
          _entries[s.studentId] ??= MarkEntry(
            studentId: s.studentId,
            studentName: s.fullName,
          );
          _focus[s.studentId] ??= FocusNode();
          _controllers[s.studentId] ??= TextEditingController();
        }
        _roster = ScreenState<List<RosterStudent>>.data(students);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _roster = ScreenState<List<RosterStudent>>.failed(
            f,
            cached: _roster.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  List<RosterStudent> get _students => _roster.data ?? const [];

  int get _enteredCount =>
      _entries.values.where((e) => e.isEntered).length;

  /// Rows that cannot be sent, so the count is honest about what "done"
  /// means.
  int get _problemCount => _entries.values
      .where((e) => e.problem(widget.paper.maxMarks) != null)
      .length;

  bool get _canSave =>
      !_saving && !widget.marksLocked && _enteredCount > 0 && _problemCount == 0;

  void _update(String studentId, MarkEntry next) {
    setState(() {
      _entries[studentId] = next;
      _saved = null;
    });
  }

  /// Moves to the next student's field. Bound to both Tab and Enter, so the
  /// two keys a teacher reaches for do the same, safe thing.
  void _focusNext(String studentId) {
    final order = _students;
    final i = order.indexWhere((s) => s.studentId == studentId);
    if (i < 0 || i + 1 >= order.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    _focus[order[i + 1].studentId]?.requestFocus();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    final outcome = await widget.repository.saveMarks(
      examSubjectId: widget.paper.id,
      entries: _entries.values.toList(),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = outcome.error;
      _saved = outcome.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(
        backgroundColor: t.surface,
        surfaceTintColor: t.surface,
        iconTheme: IconThemeData(color: t.textPrimary),
        title: Text(
          'Marks',
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Header(paper: widget.paper, examName: widget.examName),

            if (widget.marksLocked)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                  vertical: AppSpacing.space3,
                ),
                child: InlineAlert(
                  tone: InlineAlertTone.warning,
                  message: 'This exam has been published, so its marks are '
                      'locked and can no longer be changed.',
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                  vertical: AppSpacing.space3,
                ),
                // Two facts a teacher needs BEFORE typing forty numbers.
                child: InlineAlert(
                  tone: InlineAlertTone.info,
                  message: 'Marks already saved cannot be shown — this system '
                      'has no way to read them back. Saving again replaces '
                      'whatever is stored. Once the exam is published, marks '
                      'are locked for good.',
                ),
              ),

            // The summary sits ABOVE the list, so "how many left" never
            // costs a scroll to the bottom of forty rows.
            _Summary(
              entered: _enteredCount,
              total: _students.length,
              problems: _problemCount,
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                  vertical: AppSpacing.space3,
                ),
                child:
                    InlineAlert(tone: InlineAlertTone.danger, message: _error!),
              ),

            // D-29: submit confirmation, 250ms then settle — the ONLY
            // overshoot in the product. Forty numbers typed by hand deserve
            // an acknowledgement that lands rather than one that blinks in.
            if (_saved != null)
              MotionConfirm(
                show: true,
                child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                  vertical: AppSpacing.space3,
                ),
                child: InlineAlert(
                  tone: _saved!.allSaved
                      ? InlineAlertTone.success
                      : InlineAlertTone.warning,
                  message: _saved!.allSaved
                      ? '${_saved!.successCount} '
                          '${_saved!.successCount == 1 ? 'mark' : 'marks'} saved.'
                      : '${_saved!.successCount} saved, '
                          '${_saved!.errorCount} could not be: '
                          '${_saved!.errors.join('; ')}',
                ),
              ),
              ),

            Expanded(
              child: ScreenStateBuilder<List<RosterStudent>>(
                state: _roster,
                onRetry: _load,
                emptyTitle: 'No students enrolled',
                emptyMessage: 'This section has no enrolled students, so '
                    'there is nothing to mark.',
                emptyIcon: Icons.groups_outlined,
                data: (context, students) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  itemCount: students.length,
                  itemBuilder: (context, i) {
                    final s = students[i];
                    final entry = _entries[s.studentId]!;
                    return MarkRow(
                      entry: entry,
                      maxMarks: widget.paper.maxMarks,
                      enabled: !widget.marksLocked && !_saving,
                      focusNode: _focus[s.studentId]!,
                      controller: _controllers[s.studentId]!,
                      onChanged: (text) => _update(
                        s.studentId,
                        entry.copyWith(text: text, isAbsent: false),
                      ),
                      onToggleAbsent: () {
                        final nowAbsent = !entry.isAbsent;
                        // Clearing the number is what keeps the two from
                        // ever disagreeing about the same student.
                        if (nowAbsent) _controllers[s.studentId]!.clear();
                        _update(
                          s.studentId,
                          entry.copyWith(
                            isAbsent: nowAbsent,
                            text: nowAbsent ? '' : entry.text,
                          ),
                        );
                      },
                      onNext: () => _focusNext(s.studentId),
                    );
                  },
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: AppButton(
                label: _saving ? 'Saving…' : 'Save marks',
                fullWidth: true,
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.paper, required this.examName});

  final ExamPaper paper;
  final String examName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space6,
        AppSpacing.space4,
        AppSpacing.space6,
        AppSpacing.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            examName,
            style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            '${paper.subjectName.isEmpty ? 'Subject' : paper.subjectName}'
            '${paper.sectionName.isEmpty ? '' : ' · ${paper.sectionName}'}'
            ' · out of ${paper.maxMarks.format()}'
            ' · pass ${paper.passingMarks.format()}',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Entered / total, and anything that is wrong. Always on screen.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.entered,
    required this.total,
    required this.problems,
  });

  final int entered;
  final int total;
  final int problems;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final remaining = total - entered;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space6,
        vertical: AppSpacing.space3,
      ),
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$entered of $total entered',
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          if (remaining > 0)
            Text(
              '$remaining left',
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
            ),
          if (problems > 0)
            Text(
              problems == 1 ? '1 needs fixing' : '$problems need fixing',
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.dangerTextOnBg),
            ),
        ],
      ),
    );
  }
}

/// One student's row: name, a number field, an absent toggle.
class MarkRow extends StatelessWidget {
  const MarkRow({
    required this.entry,
    required this.maxMarks,
    required this.enabled,
    required this.focusNode,
    required this.controller,
    required this.onChanged,
    required this.onToggleAbsent,
    required this.onNext,
    super.key,
  });

  final MarkEntry entry;
  final Marks maxMarks;
  final bool enabled;
  final FocusNode focusNode;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleAbsent;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final problem = entry.problem(maxMarks);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space2),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space2,
      ),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: problem != null ? t.danger : t.border,
          width: AppSizing.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: a long name, a field and a toggle cannot share a
          // line at a large text scale on a 360px phone.
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: AppSizing.avatar56),
                child: Text(
                  entry.studentName,
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
              ),
              SizedBox(
                width: AppSizing.marksFieldWidth,
                child: Focus(
                  // Tab and Enter both move on, and neither submits. A
                  // stray Enter halfway down a class must never save.
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                        event.logicalKey == LogicalKeyboardKey.tab) {
                      onNext();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled && !entry.isAbsent,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    onChanged: onChanged,
                    onSubmitted: (_) => onNext(),
                    style: AppTypography.personName
                        .copyWith(color: t.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: entry.isAbsent ? '—' : maxMarks.format(),
                      hintStyle: AppTypography.bodyAdminMeta
                          .copyWith(color: t.textSecondary),
                    ),
                  ),
                ),
              ),
              _AbsentToggle(
                absent: entry.isAbsent,
                enabled: enabled,
                onTap: onToggleAbsent,
                studentName: entry.studentName,
              ),
            ],
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space1),
              child: Text(
                problem,
                style:
                    AppTypography.bodyAdminMeta.copyWith(color: t.dangerTextOnBg),
              ),
            ),
        ],
      ),
    );
  }
}

/// Absent as a single tap, not a dropdown.
class _AbsentToggle extends StatelessWidget {
  const _AbsentToggle({
    required this.absent,
    required this.enabled,
    required this.onTap,
    required this.studentName,
  });

  final bool absent;
  final bool enabled;
  final VoidCallback onTap;
  final String studentName;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      toggled: absent,
      label: '$studentName absent',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: absent ? t.warningBg : t.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: absent ? t.warning : t.border,
                width: AppSizing.borderThin,
              ),
            ),
            child: Text(
              'Absent',
              style: AppTypography.fieldLabel.copyWith(
                color: absent ? t.warningTextOnBg : t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

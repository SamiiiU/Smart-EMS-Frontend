import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/page_header.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

/// Batch assessments. Instructors (exam.marks.enter) and managers create and
/// mark drafts; publishing needs exam.manage + academy.manage on the campus.
/// Drafts are never shown to learners or guardians; published marks are
/// frozen (the server and a database trigger enforce both).
class AssessmentsTab extends StatefulWidget {
  const AssessmentsTab({
    required this.repository,
    required this.batch,
    required this.canPublish,
    super.key,
  });
  final AcademyRepository repository;
  final Batch batch;
  final bool canPublish;

  @override
  State<AssessmentsTab> createState() => _AssessmentsTabState();
}

class _AssessmentsTabState extends State<AssessmentsTab> {
  final _loader = GlobalKey<AcademyLoaderState<List<Assessment>>>();

  Future<void> _create() async {
    var title = '', max = '', on = isoDate(DateTime.now());
    final ok = await showFormDialog(
      context,
      title: 'New assessment',
      submitLabel: 'Create draft',
      canSubmit: () =>
          title.trim().isNotEmpty &&
          isDecimal2(max) &&
          (double.tryParse(max) ?? 0) > 0 &&
          isDate(on),
      fields: (context, setState) => Column(
        children: [
          field(
            'Title',
            title,
            (v) => setState(() => title = v),
            placeholder: 'e.g. Unit test 1',
            required: true,
          ),
          field(
            'Maximum marks',
            max,
            (v) => setState(() => max = v),
            placeholder: 'e.g. 25',
            required: true,
            error: max.isEmpty || isDecimal2(max)
                ? null
                : 'A number with up to two decimals.',
          ),
          field(
            'Date',
            on,
            (v) => setState(() => on = v),
            placeholder: 'YYYY-MM-DD',
            required: true,
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.createAssessment(
          widget.batch.id,
          title.trim(),
          max.trim(),
          on.trim(),
        ),
      ),
    );
    if (ok) await _loader.currentState?.reload();
  }

  void _open(Assessment a) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => MarksScreen(
            repository: widget.repository,
            assessmentId: a.id,
            canPublish: widget.canPublish,
          ),
        ),
      )
      .then((_) => _loader.currentState?.reload());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'New assessment',
              icon: Icons.add,
              onPressed: widget.batch.status == 'cancelled' ? null : _create,
            ),
          ),
        ),
        Expanded(
          child: AcademyLoader<List<Assessment>>(
            key: _loader,
            load: () => widget.repository.assessments(widget.batch.id),
            isEmpty: (v) => v.isEmpty,
            emptyTitle: 'No assessments yet',
            emptyMessage:
                'Create a draft, enter marks, then publish it to learners and guardians.',
            emptyIcon: Icons.assignment_outlined,
            builder: (context, rows, _) => SizedBox.expand(
              child: AdaptiveDataView<Assessment>(
                rows: rows,
                onTap: _open,
                semanticLabel: (a) =>
                    '${a.title}, out of ${a.maxMarks}, ${a.status}',
                columns: [
                  DataColumnSpec(
                    label: 'Assessment',
                    value: (a) => a.title,
                    flex: 2,
                  ),
                  DataColumnSpec(label: 'Date', value: (a) => a.assessedOn),
                  DataColumnSpec(
                    label: 'Out of',
                    value: (a) => a.maxMarks,
                    numeric: true,
                  ),
                  DataColumnSpec(
                    label: 'Status',
                    value: (a) => a.status,
                    cell: (a) => StatusChip(a.status),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Marks entry for one assessment, over the batch's active roster.
class MarksScreen extends StatefulWidget {
  const MarksScreen({
    required this.repository,
    required this.assessmentId,
    required this.canPublish,
    super.key,
  });
  final AcademyRepository repository;
  final String assessmentId;
  final bool canPublish;

  @override
  State<MarksScreen> createState() => _MarksScreenState();
}

class _MarksScreenState extends State<MarksScreen> {
  final _loader = GlobalKey<AcademyLoaderState<_MarksData>>();
  final Map<String, String> _marks = {};
  final Map<String, bool> _absent = {};
  bool _saving = false;
  String? _message;
  bool _error = false;

  Future<_MarksData> _fetch() async {
    final m = await widget.repository.marks(widget.assessmentId);
    final roster = await widget.repository.roster(m.assessment.batchId);
    _marks.clear();
    _absent.clear();
    for (final e in m.marks) {
      _marks[e.studentId] = e.marks ?? '';
      _absent[e.studentId] = e.absent;
    }
    return _MarksData(m.assessment, roster);
  }

  String? _rowError(String studentId, String max) {
    final v = _marks[studentId]?.trim() ?? '';
    if (v.isEmpty || _absent[studentId] == true) return null;
    if (!isDecimal2(v)) return 'Up to two decimals';
    if ((double.tryParse(v) ?? 0) > (double.tryParse(max) ?? 0)) {
      return 'More than $max';
    }
    return null;
  }

  Future<void> _save(_MarksData d) async {
    final rows = [
      for (final r in d.roster)
        if ((_marks[r.studentId]?.trim().isNotEmpty ?? false) ||
            _absent[r.studentId] == true)
          (
            studentId: r.studentId,
            marks: _absent[r.studentId] == true
                ? null
                : _marks[r.studentId]!.trim(),
            absent: _absent[r.studentId] == true,
            remarks: null,
          ),
    ];
    if (rows.isEmpty) return;
    if (d.roster.any(
      (r) => _rowError(r.studentId, d.assessment.maxMarks) != null,
    )) {
      return setState(() {
        _message = 'Fix the highlighted marks first.';
        _error = true;
      });
    }
    setState(() => _saving = true);
    final m = await attempt(
      () => widget.repository.saveMarks(widget.assessmentId, rows),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = m ?? 'Marks saved (still a draft — not visible to learners).';
      _error = m != null;
    });
    if (m == null) await _loader.currentState?.reload();
  }

  Future<void> _publish() async {
    if (!await confirmAction(
      context,
      title: 'Publish results?',
      message:
          'Learners and guardians will see these marks. Published marks cannot be changed.',
      confirmLabel: 'Publish',
      irreversible: true,
    )) {
      return;
    }
    final m = await attempt(
      () => widget.repository.publish(widget.assessmentId),
    );
    if (!mounted) return;
    setState(() {
      _message = m ?? 'Published.';
      _error = m != null;
    });
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: AcademyLoader<_MarksData>(
          key: _loader,
          load: _fetch,
          emptyTitle: 'Assessment not available',
          emptyMessage: 'It does not exist or is not available to you.',
          builder: (context, d, _) {
            final a = d.assessment;
            final frozen = a.published;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: PageHeader(
                        title: a.title,
                        subtitle: '${a.assessedOn} · out of ${a.maxMarks}',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.space6),
                      child: StatusChip(a.status),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (frozen)
                        const InlineAlert(
                          tone: InlineAlertTone.info,
                          message: 'Published — marks are read-only.',
                        )
                      else
                        const InlineAlert(
                          tone: InlineAlertTone.info,
                          message:
                              'Draft — learners and guardians cannot see these marks until published.',
                        ),
                      if (_message != null) ...[
                        const SizedBox(height: AppSpacing.space4),
                        InlineAlert(
                          tone: _error
                              ? InlineAlertTone.danger
                              : InlineAlertTone.success,
                          message: _message!,
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: d.roster.isEmpty
                      ? const Center(
                          child: Text('No active learners in this batch.'),
                        )
                      : SizedBox.expand(
                          child: AdaptiveDataView<RosterEntry>(
                            rows: d.roster,
                            semanticLabel: (r) =>
                                '${r.name}, marks ${_marks[r.studentId] ?? 'none'}',
                            columns: [
                              DataColumnSpec(
                                label: 'Learner',
                                value: (r) => r.name,
                                flex: 2,
                              ),
                              DataColumnSpec(
                                label: 'Marks',
                                value: (r) => _marks[r.studentId] ?? '',
                                // An input while draft: must stay reachable
                                // by screen readers (Android TalkBack, report 11).
                                interactive: !frozen,
                                cell: (r) => frozen
                                    ? Text(
                                        _absent[r.studentId] == true
                                            ? 'Absent'
                                            : (_marks[r.studentId]?.isEmpty ??
                                                  true)
                                            ? '—'
                                            : _marks[r.studentId]!,
                                      )
                                    : SizedBox(
                                        width: 120,
                                        child: TextFormField(
                                          key: ValueKey('marks-${r.studentId}'),
                                          initialValue:
                                              _marks[r.studentId] ?? '',
                                          enabled: _absent[r.studentId] != true,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            errorText: _rowError(
                                              r.studentId,
                                              a.maxMarks,
                                            ),
                                            hintText: '0–${a.maxMarks}',
                                          ),
                                          onChanged: (v) => setState(
                                            () => _marks[r.studentId] = v,
                                          ),
                                        ),
                                      ),
                              ),
                              DataColumnSpec(
                                label: 'Absent',
                                value: (r) =>
                                    _absent[r.studentId] == true ? 'yes' : 'no',
                                interactive: !frozen,
                                cell: (r) => Checkbox(
                                  value: _absent[r.studentId] ?? false,
                                  onChanged: frozen
                                      ? null
                                      : (v) => setState(
                                          () =>
                                              _absent[r.studentId] = v ?? false,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                if (!frozen)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.space6),
                    child: Wrap(
                      spacing: AppSpacing.space5,
                      runSpacing: AppSpacing.space5,
                      children: [
                        AppButton(
                          label: _saving ? 'Saving…' : 'Save marks',
                          onPressed: _saving ? null : () => _save(d),
                        ),
                        if (widget.canPublish)
                          AppButton(
                            label: 'Publish',
                            variant: AppButtonVariant.secondary,
                            onPressed: _saving ? null : _publish,
                          )
                        else
                          Text(
                            'Publishing needs an administrator with exam management on this campus.',
                            style: AppTypography.bodyAdminMeta.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MarksData {
  const _MarksData(this.assessment, this.roster);
  final Assessment assessment;
  final List<RosterEntry> roster;
}

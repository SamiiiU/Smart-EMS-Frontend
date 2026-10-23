import 'package:flutter/material.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/theme/scales.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/job_progress.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../admin/domain/people_models.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';

/// Explicit requirements for one section; partial solutions never replace slots.
class TimetableGenerationPanel extends StatefulWidget {
  const TimetableGenerationPanel({
    required this.repository,
    required this.campusId,
    required this.yearId,
    required this.sectionId,
    required this.subjects,
    required this.staff,
    required this.onApplied,
    required this.onBusy,
    super.key,
  });
  final SetupRepository repository;
  final String campusId, yearId, sectionId;
  final List<Subject> subjects;
  final List<PersonAccount> staff;
  final VoidCallback onApplied;
  final void Function(bool) onBusy;
  @override
  State<TimetableGenerationPanel> createState() =>
      _TimetableGenerationPanelState();
}

class _TimetableGenerationPanelState extends State<TimetableGenerationPanel> {
  final Map<String, ({String teacher, int periods})> _requirements = {};
  String? _subject, _teacher, _jobId, _message;
  int _periods = 1;
  bool _replace = false, _busy = false;
  Future<void> _generate() async {
    if (_busy || _requirements.isEmpty) return;
    final approved = await confirmAction(
      context,
      title: 'Generate this section’s timetable?',
      message: _replace
          ? 'A complete solution replaces this section’s existing slots. Partial solutions leave them unchanged.'
          : 'Generate from these requirements. Existing slots are preserved; a populated section requires explicit replacement.',
      confirmLabel: 'Generate',
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    widget.onBusy(true);
    try {
      final job = await widget.repository.generateTimetable({
        'campusId': widget.campusId,
        'academicYearId': widget.yearId,
        'clearExisting': _replace,
        'sections': [
          {
            'sectionId': widget.sectionId,
            'subjects': [
              for (final row in _requirements.entries)
                {
                  'subjectId': row.key,
                  'preferredTeacherId': row.value.teacher,
                  'periodsPerWeek': row.value.periods,
                },
            ],
          },
        ],
      });
      if (mounted) setState(() => _jobId = job['jobId'] as String);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error is LoadFailure
            ? error.message ?? 'Generation could not be queued.'
            : 'Generation could not be queued.';
      });
      widget.onBusy(false);
    }
  }

  void _finish(Map<String, dynamic> job) {
    final result = (job['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    setState(() {
      _busy = false;
      _jobId = null;
      _message = job['error_code'] == 'input_changed'
          ? 'Timetable inputs changed. Review your requirements and submit a fresh request.'
          : job['status'] != 'completed'
          ? 'Generation stopped. Existing slots were preserved.'
          : result['applied'] == true
          ? '${result['generatedSlots']} slots generated and saved.'
          : 'A complete timetable could not be found. ${result['conflictSlots']} conflicting lessons; existing slots were preserved. Adjust requirements before trying again.';
    });
    widget.onBusy(false);
    if (result['applied'] == true) widget.onApplied();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const InlineAlert(
        tone: InlineAlertTone.info,
        message:
            'Automatic timetable: choose each subject, teacher and weekly lesson count. This generates only the selected section.',
      ),
      if (widget.subjects.isEmpty || widget.staff.isEmpty)
        const InlineAlert(
          tone: InlineAlertTone.warning,
          message: 'Load subjects and staff before generating.',
        ),
      AbsorbPointer(
        absorbing: _busy,
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _subject,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                for (final s in widget.subjects)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (value) => setState(() => _subject = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: _teacher,
              decoration: const InputDecoration(labelText: 'Teacher'),
              items: [
                for (final s in widget.staff)
                  DropdownMenuItem(value: s.id, child: Text(s.fullName)),
              ],
              onChanged: (value) => setState(() => _teacher = value),
            ),
            DropdownButtonFormField<int>(
              initialValue: _periods,
              decoration: const InputDecoration(labelText: 'Lessons per week'),
              items: [
                for (int i = 1; i <= 36; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (value) => setState(() => _periods = value ?? 1),
            ),
            const SizedBox(height: AppSpacing.space3),
            AppButton(
              label: 'Add requirement',
              variant: AppButtonVariant.secondary,
              onPressed:
                  _subject == null ||
                      _teacher == null ||
                      _requirements.length >= 50
                  ? null
                  : () => setState(
                      () => _requirements[_subject!] = (
                        teacher: _teacher!,
                        periods: _periods,
                      ),
                    ),
            ),
            for (final row in _requirements.entries)
              ListTile(
                title: Text(
                  widget.subjects.firstWhere((s) => s.id == row.key).name,
                ),
                subtitle: Text(
                  '${widget.staff.firstWhere((s) => s.id == row.value.teacher).fullName}: ${row.value.periods} lessons/week',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove requirement',
                  onPressed: () =>
                      setState(() => _requirements.remove(row.key)),
                ),
              ),
            CheckboxListTile(
              value: _replace,
              title: const Text(
                'Replace existing slots only when a complete solution is found',
              ),
              onChanged: (value) => setState(() => _replace = value ?? false),
            ),
          ],
        ),
      ),
      AppButton(
        label: _busy ? 'Generating…' : 'Generate timetable',
        onPressed: _busy || _requirements.isEmpty ? null : _generate,
      ),
      if (_jobId != null)
        JobProgress(
          key: ValueKey(_jobId),
          jobId: _jobId!,
          load: (token) => widget.repository.loadWorkflow(_jobId!, token),
          onFinished: _finish,
        ),
      if (_message != null)
        InlineAlert(tone: InlineAlertTone.info, message: _message!),
      const SizedBox(height: AppSpacing.space6),
    ],
  );
}

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/scales.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/form_field_decoration.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/job_progress.dart';
import '../../admin/presentation/workflow_jobs_screen.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../setup/domain/setup_models.dart';

/// DEF-20: the proposal is shown as readable lines, never as a raw JSON dump.
List<String> proposalLines(Object? value, [String indent = '']) {
  if (value is Map) {
    return [
      for (final entry in value.entries)
        if (entry.value is Map || entry.value is List) ...[
          '$indent${_humanKey('${entry.key}')}:',
          ...proposalLines(entry.value, '$indent  '),
        ] else
          '$indent${_humanKey('${entry.key}')}: ${entry.value}',
    ];
  }
  if (value is List) {
    return [
      for (final item in value)
        if (item is Map || item is List)
          ...proposalLines(item, indent)
        else
          '$indent- $item',
    ];
  }
  return ['$indent$value'];
}

String _humanKey(String key) {
  final words = key
      .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .toLowerCase();
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

class AcademicAiScreen extends StatefulWidget {
  const AcademicAiScreen({
    required this.dio,
    required this.subjects,
    required this.sections,
    required this.classes,
    required this.years,
    super.key,
  });
  final Dio dio;
  final List<Subject> subjects;
  final List<Section> sections;
  final List<SchoolClass> classes;
  final List<AcademicYear> years;
  @override
  State<AcademicAiScreen> createState() => _AcademicAiScreenState();
}

class _AcademicAiScreenState extends State<AcademicAiScreen> {
  final _source = TextEditingController(),
      _marks = TextEditingController(text: '10.00');
  final _due = TextEditingController(
    text: DateTime.now()
        .add(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10),
  );
  String _mode = 'assignment';
  String? _subject,
      _section,
      _class,
      _year,
      _assignment,
      _submission,
      _job,
      _error,
      _pdf,
      _pdfName,
      _key,
      _signature,
      _message;
  List<Map<String, dynamic>> _assignments = [], _submissions = [];
  bool _loadingRecords = false;
  Map<String, dynamic>? _result;
  final Set<String> _approved = {};
  bool _busy = false;
  @override
  void dispose() {
    _source.dispose();
    _marks.dispose();
    _due.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    setState(() => _loadingRecords = true);
    try {
      final r = await widget.dio.get<List<dynamic>>('/api/assignments');
      if (mounted) {
        setState(
          () => _assignments = (r.data ?? []).cast<Map<String, dynamic>>(),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Assignments could not be loaded. Check permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRecords = false);
    }
  }

  Future<void> _loadSubmissions(String assignment) async {
    setState(() => _loadingRecords = true);
    try {
      final r = await widget.dio.get<List<dynamic>>(
        '/api/assignments/$assignment/submissions',
      );
      if (mounted) {
        setState(
          () => _submissions = (r.data ?? []).cast<Map<String, dynamic>>(),
        );
      }
    } on Object {
      if (mounted) setState(() => _error = 'Submissions could not be loaded.');
    } finally {
      if (mounted) setState(() => _loadingRecords = false);
    }
  }

  Future<void> _pickPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 1048576) {
      setState(
        () => _error = 'Choose a searchable PDF of at most 1 MB and 30 pages.',
      );
      return;
    }
    setState(() {
      _pdf = base64Encode(bytes);
      _pdfName = file.name;
      _source.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_mode != 'grading' && (_subject == null || _year == null) ||
        _mode == 'assignment' && _section == null ||
        _mode == 'syllabus' && _class == null ||
        _mode == 'grading' && _submission == null) {
      setState(() => _error = 'Choose the required academic records first.');
      return;
    }
    if (_mode == 'assignment' &&
        (DateTime.tryParse(_due.text) == null ||
            !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(_marks.text.trim()))) {
      setState(
        () => _error = 'Enter a valid due date and decimal maximum marks.',
      );
      return;
    }
    final path = switch (_mode) {
      'assignment' => '/api/ai/assignments',
      'syllabus' => '/api/ai/syllabus',
      _ => '/api/ai/grading/$_submission',
    };
    final Map<String, dynamic> body = switch (_mode) {
      'assignment' => {
        'subjectId': _subject,
        'sectionId': _section,
        'academicYearId': _year,
        'dueDate': _due.text.trim(),
        'maxMarks': _marks.text.trim(),
        'topicContext': _source.text.trim(),
      },
      'syllabus' => {
        'subjectId': _subject,
        'classId': _class,
        'academicYearId': _year,
        'sourceText': _pdf == null ? _source.text.trim() : null,
        'pdfBase64': _pdf,
      },
      _ => {'rubric': _source.text.trim()},
    };
    final signature = path + jsonEncode(body);
    if (_signature != signature) {
      _signature = signature;
      _key = const Uuid().v4();
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _result = null;
    });
    try {
      final response = await widget.dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(headers: {'Idempotency-Key': _key}),
      );
      if (mounted) setState(() => _job = response.data!['jobId'] as String);
    } on DioException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          final body = error.response?.data;
          _error = body is Map && body['message'] is String
              ? body['message'] as String
              : 'Submission outcome is unknown. Check Background jobs before sending again.';
        });
      }
    }
  }

  Future<void> _review(String path, Object? body, String done) async {
    // Shared accessible confirmation: focus starts on Cancel; Escape cancels (D-07 pattern).
    final confirm = await confirmAction(
      context,
      title: 'Confirm your review?',
      message:
          'Only continue after checking the source and every proposed item. This applies your decision to the academic records.',
      confirmLabel: 'Confirm',
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.dio.post<dynamic>(path, data: body);
      // DEF-21: a confirmed review says what happened.
      if (mounted) {
        setState(() {
          _result = null;
          _message = done;
        });
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.response?.data is Map
              ? (error.response!.data['message'] as String? ?? 'Review failed.')
              : 'Review outcome could not be confirmed. Check records before repeating.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _picker(
    String label,
    String? value,
    List<(String, String)> choices,
    void Function(String?) change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey(
      '$label:$_mode:$value:${choices.map((choice) => choice.$1).join()}',
    ),
    initialValue: value,
    decoration: appFormDecoration(context, label: label),
    isExpanded: true,
    items: [
      for (final choice in choices)
        DropdownMenuItem(value: choice.$1, child: Text(choice.$2)),
    ],
    onChanged: _busy ? null : change,
  );
  @override
  Widget build(BuildContext context) {
    final result = _result,
        proposal = (result?['proposal'] as Map?)?.cast<String, dynamic>();
    final topics = <String>[];
    if (proposal?['chapters'] is List) {
      for (final chapter in proposal!['chapters']) {
        for (final topic in chapter['topics']) {
          topics.add('${chapter['name']}: $topic');
        }
      }
    }
    final ids = (result?['topicIds'] as List?)?.cast<String>() ?? [];
    return Scaffold(
      backgroundColor: context.tokens.page,
      appBar: AppBar(title: const Text('AI teaching assistant')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.space4,
          children: [
            const InlineAlert(
              tone: InlineAlertTone.info,
              message:
                  'AI creates proposals for your review. It never publishes an assignment or finalizes a student grade. Use source material you are authorized to share.',
            ),
            _picker(
              'Task',
              _mode,
              const [
                ('assignment', 'Assignment draft'),
                ('syllabus', 'Syllabus extraction'),
                ('grading', 'Grading suggestion'),
              ],
              (value) {
                setState(() {
                  _mode = value!;
                  _result = null;
                  _source.clear();
                  _pdf = null;
                  _pdfName = null;
                });
                if (value == 'grading') _loadAssignments();
              },
            ),
            if (_mode != 'grading') ...[
              _picker('Subject', _subject, [
                for (final s in widget.subjects) (s.id, s.name),
              ], (v) => setState(() => _subject = v)),
              _picker(
                'Academic year',
                _year,
                [for (final y in widget.years) (y.id, y.name)],
                (v) => setState(() {
                  _year = v;
                  _section = null;
                }),
              ),
            ],
            if (_mode == 'assignment') ...[
              _picker('Section', _section, [
                for (final s in widget.sections.where(
                  (s) => s.academicYearId == _year,
                ))
                  (s.id, s.name),
              ], (v) => setState(() => _section = v)),
              TextField(
                controller: _due,
                enabled: !_busy,
                decoration: appFormDecoration(
                  context,
                  label: 'Due date (YYYY-MM-DD)',
                ),
              ),
              TextField(
                controller: _marks,
                enabled: !_busy,
                decoration: appFormDecoration(context, label: 'Maximum marks'),
              ),
            ],
            if (_mode == 'syllabus') ...[
              _picker('Class', _class, [
                for (final c in widget.classes) (c.id, c.name),
              ], (v) => setState(() => _class = v)),
              AppButton(
                label: 'Choose searchable PDF',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _pickPdf,
              ),
              if (_pdfName != null)
                Text(
                  'Selected: $_pdfName (text PDFs only; scans need OCR first)',
                ),
            ],
            if (_mode == 'grading') ...[
              _picker(
                'Assignment',
                _assignment,
                [
                  for (final a in _assignments)
                    (a['id'] as String, a['title'] as String),
                ],
                (v) {
                  setState(() {
                    _assignment = v;
                    _submission = null;
                    _submissions = [];
                  });
                  _loadSubmissions(v!);
                },
              ),
              if (_loadingRecords)
                Semantics(
                  liveRegion: true,
                  label: 'Loading records',
                  child: const LinearProgressIndicator(),
                ),
              if (!_loadingRecords && _assignments.isEmpty)
                const InlineAlert(
                  tone: InlineAlertTone.info,
                  message:
                      'No assignments yet. Create and publish an assignment before asking for a grading suggestion.',
                ),
              if (!_loadingRecords &&
                  _assignment != null &&
                  _submissions.isEmpty)
                const InlineAlert(
                  tone: InlineAlertTone.info,
                  message: 'No submissions for this assignment yet.',
                ),
              _picker('Submission', _submission, [
                for (final s in _submissions)
                  (s['submission_id'] as String, s['student_name'] as String),
              ], (v) => setState(() => _submission = v)),
            ],
            TextField(
              controller: _source,
              enabled: !_busy,
              maxLines: 6,
              maxLength: _mode == 'syllabus' ? 40000 : 20000,
              decoration: appFormDecoration(
                context,
                label: _mode == 'grading'
                    ? 'Teacher rubric (criteria and marks)'
                    : _mode == 'syllabus'
                    ? 'Syllabus text (or choose a PDF)'
                    : 'Source material, level and desired learning goals',
              ),
              onChanged: (_) {
                if (_pdf != null) {
                  setState(() {
                    _pdf = null;
                    _pdfName = null;
                  });
                }
              },
            ),
            AppButton(
              label: _busy ? 'Processing…' : 'Create proposal',
              onPressed: _busy ? null : _submit,
            ),
            AppButton(
              label: 'Background jobs',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => WorkflowJobsScreen(dio: widget.dio),
                ),
              ),
            ),
            if (_job != null)
              JobProgress(
                key: ValueKey(_job),
                jobId: _job!,
                load: (token) async =>
                    (await widget.dio.get<Map<String, dynamic>>(
                      '/api/workflow-jobs/$_job',
                      cancelToken: token,
                    )).data!,
                onFinished: (job) => setState(() {
                  _job = null;
                  _busy = false;
                  _approved.clear();
                  if (job['status'] == 'completed') {
                    _result = (job['result'] as Map).cast<String, dynamic>();
                    _signature = null;
                    _key = null;
                  } else {
                    _error =
                        'The proposal job stopped. Review it in Background jobs before retrying.';
                  }
                }),
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: InlineAlert(
                  tone: InlineAlertTone.danger,
                  message: _error!,
                ),
              ),
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: InlineAlert(
                  tone: InlineAlertTone.success,
                  message: _message!,
                ),
              ),
            if (proposal != null) ...[
              const Text('Review the proposal against your source'),
              for (final line in proposalLines(proposal)) SelectableText(line),
              if (result?['assignmentId'] != null)
                AppButton(
                  label: 'Publish reviewed draft',
                  onPressed: _busy
                      ? null
                      : () => _review(
                          '/api/assignments/${result!['assignmentId']}/publish',
                          null,
                          'Assignment published. Students can now see it.',
                        ),
                ),
              for (int i = 0; i < ids.length && i < topics.length; i++)
                CheckboxListTile(
                  value: _approved.contains(ids[i]),
                  title: Text(topics[i]),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _approved.add(ids[i]);
                          } else {
                            _approved.remove(ids[i]);
                          }
                        }),
                ),
              if (result?['proposalId'] != null)
                AppButton(
                  label: 'Apply reviewed syllabus selection',
                  onPressed: _busy
                      ? null
                      : () => _review(
                          '/api/syllabus/proposals/${result!['proposalId']}/approve',
                          {'approvedTopicIds': _approved.toList()},
                          'Syllabus selection applied: ${_approved.length} topic(s) approved; unselected topics were discarded.',
                        ),
                ),
              if (result?['submissionId'] != null)
                const InlineAlert(
                  tone: InlineAlertTone.info,
                  message:
                      'Suggested marks are saved separately. A teacher must grade the submission through the normal grading flow; no final marks were changed.',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

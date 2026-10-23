import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/job_progress.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/states/empty_state.dart';

/// Human wording for job statuses; unknown values are shown as received.
String workflowStatusLabel(Object? s) => switch (s) {
  'pending' => 'Pending',
  'processing' => 'Running',
  'completed' => 'Completed',
  'failed' => 'Failed',
  'closed' => 'Closed',
  null => 'Unknown',
  _ => '$s',
};

/// Human wording for job kinds; the raw code stays visible as a caption for support.
String workflowKindLabel(Object? kind) => switch (kind) {
  null => 'Report PDF',
  'INVOICES' => 'Invoice generation',
  // Values from the workflow_job_kind_check constraint (V1–V62).
  'IMPORT' => 'Data import',
  'TIMETABLE' => 'Timetable generation',
  'AI_ASSIGNMENT' => 'AI assignment draft',
  'AI_SYLLABUS' => 'AI syllabus draft',
  'AI_GRADING' => 'AI grading suggestions',
  'MAILBOX_VERIFY' => 'Mailbox verification',
  _ => '$kind',
};

/// Server-backed history survives browser reload without storing another user's jobs locally.
class WorkflowJobsScreen extends StatefulWidget {
  const WorkflowJobsScreen({required this.dio, super.key});
  final Dio dio;
  @override
  State<WorkflowJobsScreen> createState() => _WorkflowJobsScreenState();
}

class _WorkflowJobsScreenState extends State<WorkflowJobsScreen> {
  final _scroll = ScrollController();
  // Keyboard users land on the opened detail, and return to the row they came from.
  final _detailFocus = FocusNode(debugLabel: 'job-detail');
  final _rowFocus = <String, FocusNode>{};
  String? _openedFrom;
  FocusNode _rowNode(String id) =>
      _rowFocus.putIfAbsent(id, () => FocusNode(debugLabel: 'job-$id'));
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _selected;
  List<dynamic> _history = [];
  int _page = 0;
  bool _loading = false, _reports = false;
  String? _error, _actionKey, _actionSignature;
  String get _base =>
      _reports ? '/api/report-card-deliveries' : '/api/workflow-jobs';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _detailFocus.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.dio.get<List<dynamic>>(
        _base,
        queryParameters: {'page': _page, 'size': 20},
      );
      if (mounted) {
        setState(
          () => _rows = (response.data ?? []).cast<Map<String, dynamic>>(),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Jobs could not be loaded. Check your connection or permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _detail(String id, CancelToken token) async {
    final response = await widget.dio.get<Map<String, dynamic>>(
      '/api/workflow-jobs/$id',
      cancelToken: token,
    );
    return response.data!;
  }

  Future<void> _select(Map<String, dynamic> row) async {
    try {
      final detail = _reports
          ? row
          : await _detail(row['id'] as String, CancelToken());
      final history = await widget.dio.get<List<dynamic>>(
        '$_base/${row['id']}/history',
        queryParameters: {'page': 0, 'size': 20},
      );
      if (mounted) {
        setState(() {
          _selected = detail;
          _history = history.data ?? [];
          _error = null;
          _openedFrom = row['id'] as String?;
        });
        // The detail renders above the list: bring it into view where the user is.
        if (_scroll.hasClients) {
          await _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        if (mounted) _detailFocus.requestFocus();
      }
    } on Object {
      if (mounted) setState(() => _error = 'Job details could not be loaded.');
    }
  }

  void _closeDetails() {
    final from = _openedFrom;
    setState(() => _selected = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && from != null) _rowFocus[from]?.requestFocus();
    });
  }

  Future<void> _action(String action) async {
    final job = _selected!;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RecoveryReasonDialog(action: action),
    );
    if (reason == null || !mounted) return;
    final signature = '${job['id']}:$action:$reason';
    if (_actionSignature != signature) {
      _actionSignature = signature;
      _actionKey = const Uuid().v4();
    }
    try {
      await widget.dio.post<Map<String, dynamic>>(
        '$_base/${job['id']}/actions',
        data: {'action': action, 'reason': reason},
        options: Options(headers: {'Idempotency-Key': _actionKey}),
      );
      _actionSignature = null;
      _actionKey = null;
      if (!mounted) return;
      setState(() => _selected = null);
      await _load();
    } on DioException catch (error) {
      final body = error.response?.data;
      if (mounted) {
        setState(
          () => _error = body is Map && body['message'] is String
              ? body['message'] as String
              : 'Action outcome could not be confirmed. Refresh status before repeating.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final job = _selected;
    const gap = SizedBox(height: AppSpacing.space5);
    final caption = AppTypography.caption.copyWith(color: t.textSecondary);
    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(title: const Text('Background jobs')),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(AppSpacing.space5),
        children: [
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Failed report PDFs',
                style: AppTypography.bodyTeacher,
              ),
              subtitle: Text(
                _reports
                    ? 'Showing report-card PDF deliveries'
                    : 'Showing background jobs',
                style: caption,
              ),
              value: _reports,
              onChanged: _loading
                  ? null
                  : (value) {
                      setState(() {
                        _reports = value;
                        _selected = null;
                        _page = 0;
                      });
                      _load();
                    },
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: _loading ? 'Loading…' : 'Refresh jobs',
              icon: Icons.refresh,
              variant: AppButtonVariant.secondary,
              onPressed: _loading ? null : _load,
            ),
          ),
          gap,
          if (_loading) ...[
            Semantics(
              liveRegion: true,
              label: 'Loading jobs',
              child: const LinearProgressIndicator(),
            ),
            gap,
          ],
          if (_error != null) ...[
            InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            gap,
          ],
          if (job != null) ...[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Focus(
                    focusNode: _detailFocus,
                    child: Semantics(
                      header: true,
                      child: Text(
                        '${workflowKindLabel(job['kind'])}: ${workflowStatusLabel(job['status'])}',
                        style: AppTypography.cardHeading.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  SelectableText('Job ${job['id']}', style: caption),
                  if (!_reports &&
                      const ['pending', 'processing'].contains(job['status']))
                    JobProgress(
                      key: ValueKey(job['id']),
                      jobId: job['id'] as String,
                      load: (token) => _detail(job['id'] as String, token),
                      onFinished: (value) {
                        setState(() => _selected = value);
                        _load();
                      },
                    ),
                  if (job['result'] is Map) ...[
                    const SizedBox(height: AppSpacing.space4),
                    Text('Result', style: AppTypography.fieldLabel),
                    for (final e in (job['result'] as Map).entries)
                      Text(
                        '${e.key}: ${e.value}',
                        style: AppTypography.bodyTeacher,
                      ),
                  ] else if (job['result'] != null)
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(job['result']),
                    ),
                  if (job['error_code'] != null) ...[
                    const SizedBox(height: AppSpacing.space4),
                    Text(
                      'Reason: ${job['error_code']}',
                      style: AppTypography.bodyTeacher,
                    ),
                  ],
                  if (job['status'] == 'failed') ...[
                    const SizedBox(height: AppSpacing.space5),
                    if (job['error_code'] == 'input_changed') ...[
                      const InlineAlert(
                        tone: InlineAlertTone.info,
                        message:
                            'Retry is unavailable because the job\'s inputs changed after it ran. '
                            'Close this job and start a new one.',
                      ),
                      const SizedBox(height: AppSpacing.space4),
                    ],
                    Wrap(
                      spacing: AppSpacing.space4,
                      runSpacing: AppSpacing.space4,
                      children: [
                        AppButton(
                          label: 'Retry reviewed job',
                          onPressed: job['error_code'] == 'input_changed'
                              ? null
                              : () => _action('retry'),
                        ),
                        AppButton(
                          label: 'Close job',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => _action('close'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.space5),
                  Semantics(
                    header: true,
                    child: Text(
                      'Recent recovery history',
                      style: AppTypography.fieldLabel,
                    ),
                  ),
                  if (_history.isEmpty)
                    Text('No recovery actions yet.', style: caption),
                  for (final entry in _history)
                    Text(
                      '${entry['action']}: ${entry['reason']} (result: ${workflowStatusLabel(entry['result_status'])})',
                      style: AppTypography.bodyTeacher,
                    ),
                  const SizedBox(height: AppSpacing.space4),
                  // Close sits below the detail so the job title keeps the full width on phones.
                  AppButton(
                    label: 'Close details',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: _closeDetails,
                  ),
                ],
              ),
            ),
            gap,
          ],
          if (_rows.isEmpty && !_loading)
            const EmptyState(
              icon: Icons.work_history_outlined,
              title: 'No jobs on this page',
              message: 'Background jobs and failed report PDFs appear here.',
            ),
          if (_rows.isNotEmpty)
            SectionCard(
              padded: false,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (final row in _rows)
                      ListTile(
                        focusNode: _rowNode(row['id'] as String),
                        title: Text(
                          '${workflowKindLabel(row['kind'])}: ${workflowStatusLabel(row['status'])}',
                          style: AppTypography.bodyTeacher,
                        ),
                        subtitle: Text(
                          '${row['kind'] ?? 'REPORT_PDF'} · ${row['id']}',
                          style: caption,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _select(row),
                      ),
                  ],
                ),
              ),
            ),
          gap,
          Wrap(
            // Wraps rather than overflowing at 320px with large text.
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                label: 'Previous',
                variant: AppButtonVariant.ghost,
                onPressed: _page == 0 || _loading
                    ? null
                    : () {
                        _page--;
                        _load();
                      },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space5,
                ),
                child: Text(
                  'Page ${_page + 1}',
                  style: AppTypography.bodyTeacher,
                ),
              ),
              AppButton(
                label: 'Next',
                variant: AppButtonVariant.ghost,
                onPressed: _rows.length < 20 || _loading
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecoveryReasonDialog extends StatefulWidget {
  const _RecoveryReasonDialog({required this.action});
  final String action;
  @override
  State<_RecoveryReasonDialog> createState() => _RecoveryReasonDialogState();
}

class _RecoveryReasonDialogState extends State<_RecoveryReasonDialog> {
  String _reason = '';
  bool _attempted = false;

  void _confirm() {
    final reason = _reason.trim();
    if (reason.length >= 5) {
      Navigator.pop(context, reason);
    } else {
      setState(() => _attempted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final short = _attempted && _reason.trim().length < 5;
    return AlertDialog(
      title: Text(
        widget.action == 'retry' ? 'Retry reviewed job?' : 'Close this job?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Previously completed work remains saved. Record why this action is appropriate.',
            ),
            const SizedBox(height: AppSpacing.space5),
            AppTextField(
              key: const Key('job-action-reason'),
              label: 'Reason (at least 5 characters)',
              required: true,
              autofocus: true,
              value: _reason,
              state: short ? AppTextFieldState.error : AppTextFieldState.normal,
              errorText: short ? 'Enter at least 5 characters.' : null,
              onChanged: (v) => setState(
                () => _reason = v.length > 500 ? v.substring(0, 500) : v,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Up to 500 characters. Saved in the recovery history.',
              style: AppTypography.caption.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton(label: 'Confirm', onPressed: _confirm),
          ],
        ),
      ],
    );
  }
}

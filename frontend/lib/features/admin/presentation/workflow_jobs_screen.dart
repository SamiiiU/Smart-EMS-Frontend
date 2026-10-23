import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/scales.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/job_progress.dart';

/// Server-backed history survives browser reload without storing another user's jobs locally.
class WorkflowJobsScreen extends StatefulWidget {
  const WorkflowJobsScreen({required this.dio, super.key});
  final Dio dio;
  @override
  State<WorkflowJobsScreen> createState() => _WorkflowJobsScreenState();
}

class _WorkflowJobsScreenState extends State<WorkflowJobsScreen> {
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
        });
      }
    } on Object {
      if (mounted) setState(() => _error = 'Job details could not be loaded.');
    }
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
    final job = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Background jobs')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space5),
        children: [
          SwitchListTile(
            title: const Text('Failed report PDFs'),
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
          AppButton(
            label: _loading ? 'Loading…' : 'Refresh jobs',
            onPressed: _loading ? null : _load,
          ),
          if (_error != null)
            InlineAlert(tone: InlineAlertTone.warning, message: _error!),
          if (job != null) ...[
            const SizedBox(height: AppSpacing.space5),
            SelectableText('Job ${job['id']} — ${job['status']}'),
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
            if (job['result'] != null)
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(job['result']),
              ),
            if (job['error_code'] != null) Text('Reason: ${job['error_code']}'),
            if (job['status'] == 'failed') ...[
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
            const Text('Recent recovery history'),
            for (final entry in _history)
              Text(
                '${entry['action']} — ${entry['reason']} — ${entry['result_status']}',
              ),
          ],
          const SizedBox(height: AppSpacing.space5),
          if (_rows.isEmpty && !_loading) const Text('No jobs on this page.'),
          for (final row in _rows)
            ListTile(
              title: Text('${row['kind'] ?? 'Report PDF'} — ${row['status']}'),
              subtitle: Text('${row['id']}'),
              onTap: () => _select(row),
            ),
          Row(
            children: [
              TextButton(
                onPressed: _page == 0 || _loading
                    ? null
                    : () {
                        _page--;
                        _load();
                      },
                child: const Text('Previous'),
              ),
              Text('Page ${_page + 1}'),
              TextButton(
                onPressed: _rows.length < 20 || _loading
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                child: const Text('Next'),
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
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.action == 'retry' ? 'Retry reviewed job?' : 'Close this job?',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Previously completed work remains saved. Record why this action is appropriate.',
          ),
          TextField(
            controller: controller,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Reason (at least 5 characters)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (controller.text.trim().length >= 5) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Confirm'),
      ),
    ],
  );
}

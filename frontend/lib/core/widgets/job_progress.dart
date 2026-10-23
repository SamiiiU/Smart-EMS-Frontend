import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/scales.dart';
import 'app_button.dart';
import 'inline_alert.dart';

/// Polls only status reads. A transport error never resubmits business work.
class JobProgress extends StatefulWidget {
  const JobProgress({
    required this.jobId,
    required this.load,
    required this.onFinished,
    super.key,
  });
  final String jobId;
  final Future<Map<String, dynamic>> Function(CancelToken) load;
  final void Function(Map<String, dynamic>) onFinished;
  @override
  State<JobProgress> createState() => _JobProgressState();
}

class _JobProgressState extends State<JobProgress> with WidgetsBindingObserver {
  Timer? _timer;
  CancelToken? _request;
  bool _busy = false, _paused = false, _done = false;
  int _checks = 0, _failures = 0;
  String _message = 'Queued. Processing continues on the server.';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(Duration.zero, _check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _request?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _timer?.cancel();
    if (!_paused && !_done) _timer = Timer(Duration.zero, _check);
  }

  Future<void> _check() async {
    if (!mounted || _busy || _paused || _done) return;
    _timer?.cancel();
    if (ModalRoute.of(context)?.isCurrent == false) {
      _timer = Timer(const Duration(seconds: 5), _check);
      return;
    }
    _busy = true;
    _request = CancelToken();
    try {
      final job = await widget.load(_request!);
      if (!mounted) return;
      _failures = 0;
      _checks++;
      final status = job['status'] as String? ?? 'pending';
      _done = const ['completed', 'failed', 'closed'].contains(status);
      setState(
        () => _message = switch (status) {
          'processing' => 'Processing. Completed work is saved on the server.',
          'failed' =>
            'Processing stopped. Some work may already be saved. Review this job before starting another.',
          'closed' =>
            'This job was closed. Previously completed work remains saved.',
          'completed' => 'Completed.',
          _ => 'Queued. Processing continues on the server.',
        },
      );
      if (_done) widget.onFinished(job);
    } on Object {
      if (!mounted) return;
      _failures++;
      setState(
        () => _message =
            'Status could not be checked. The job may still be running. Check again; do not submit it again.',
      );
    } finally {
      _busy = false;
      if (mounted && !_paused && !_done && _checks < 60 && _failures < 3) {
        _timer = Timer(Duration(seconds: _failures == 0 ? 5 : 15), _check);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InlineAlert(
        tone: _failures > 0 ? InlineAlertTone.warning : InlineAlertTone.info,
        message: '$_message Job: ${widget.jobId}',
      ),
      if (!_done) ...[
        const SizedBox(height: AppSpacing.space3),
        AppButton(
          label: 'Check status',
          variant: AppButtonVariant.secondary,
          onPressed: _busy
              ? null
              : () {
                  _checks = 0;
                  _failures = 0;
                  _check();
                },
        ),
      ],
    ],
  );
}

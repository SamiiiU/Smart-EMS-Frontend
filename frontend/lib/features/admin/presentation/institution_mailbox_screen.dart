import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/widgets/confirm_dialog.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/scales.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/form_field_decoration.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/job_progress.dart';

/// Plain-language mailbox state (V32 statuses: draft, verified, enabled, paused).
String mailboxStatusLabel(String? status) => switch (status) {
  'draft' => 'Saved, not yet verified. Verify the connection before sending.',
  'verified' => 'Verified. Sending is off until you enable it.',
  'enabled' => 'Sending is on.',
  'paused' => 'Sending is paused.',
  _ => 'Status unknown. Refresh settings.',
};

/// One outgoing mailbox per institution. Passwords are write-only and never stored locally.
class InstitutionMailboxScreen extends StatefulWidget {
  const InstitutionMailboxScreen({required this.dio, super.key});
  final Dio dio;
  @override
  State<InstitutionMailboxScreen> createState() =>
      _InstitutionMailboxScreenState();
}

class _InstitutionMailboxScreenState extends State<InstitutionMailboxScreen> {
  final _host = TextEditingController(text: 'smtp.gmail.com');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  Map<String, dynamic>? _mailbox;
  bool _busy = false, _ssl = false;
  String? _error, _message, _jobId, _key, _signature;

  /// DEF-19: a save outcome is shown beside Save (the user is at the bottom of
  /// the form); other outcomes at the top, next to the status and actions.
  bool _feedbackAtForm = false;
  static const _base = '/api/institution-mailbox';
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final controller in [_host, _email, _password, _name]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _feedbackAtForm = false;
    });
    try {
      final response = await widget.dio.get<Map<String, dynamic>>(_base);
      if (!mounted) {
        return;
      }
      setState(() {
        _mailbox = response.data;
        if (_mailbox?['id'] != null) {
          _host.text = _mailbox!['host'] as String;
          _email.text = _mailbox!['from_email'] as String;
          _name.text = _mailbox!['display_name'] as String;
          _ssl = _mailbox!['ssl'] as bool;
        }
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Mailbox could not be loaded. Check your connection or permissions.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _post(
    String path,
    Object? body, {
    bool verification = false,
  }) async {
    if (_busy) {
      return;
    }
    _feedbackAtForm = path == _base;
    final signature = jsonEncode({'path': path, 'body': body});
    if (_signature != signature) {
      _signature = signature;
      _key = const Uuid().v4();
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await widget.dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(headers: {'Idempotency-Key': _key}),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _key = null;
        _signature = null;
        if (verification) {
          _jobId = response.data!['jobId'] as String;
        } else {
          _mailbox = response.data;
          _password.clear();
          _jobId = null;
          _message = 'Mailbox settings saved.';
        }
      });
    } on DioException catch (error) {
      if (mounted) {
        final data = error.response?.data;
        setState(
          () => _error = data is Map && data['message'] is String
              ? data['message'] as String
              : 'Request could not be confirmed. Refresh settings before changing or resubmitting it.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      // DEF-19: bring the form's errors into view; Save sits below the fields.
      final formContext = _form.currentContext;
      if (formContext != null) {
        await Scrollable.ensureVisible(
          formContext,
          duration: const Duration(milliseconds: 200),
        );
      }
      return;
    }
    final password = _host.text.trim().toLowerCase() == 'smtp.gmail.com'
        ? _password.text.replaceAll(' ', '')
        : _password.text;
    await _post(_base, {
      'host': _host.text.trim(),
      'port': _ssl ? 465 : 587,
      'ssl': _ssl,
      'username': _email.text.trim(),
      'password': password,
      'displayName': _name.text.trim(),
    });
  }

  Future<void> _action(String action) async {
    if (_busy) {
      return;
    }
    if (action == 'disconnect') {
      final accepted = await confirmAction(
        context,
        title: 'Disconnect institution mailbox?',
        message:
            'New emails will wait until a mailbox is enabled. Emails already being sent may still finish.',
        confirmLabel: 'Disconnect',
      );
      if (!accepted || !mounted) {
        return;
      }
    }
    await _post('$_base/${_mailbox!['id']}/actions', {'action': action});
    if (action == 'disconnect' && _error == null) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _mailbox?['status'] as String?;
    final configured = _mailbox?['id'] != null;
    final feedback = <Widget>[
      if (_error != null) ...[
        InlineAlert(message: _error!, tone: InlineAlertTone.danger),
        const SizedBox(height: AppSpacing.space4),
      ],
      if (_message != null) ...[
        Semantics(
          liveRegion: true,
          child: InlineAlert(message: _message!, tone: InlineAlertTone.success),
        ),
        const SizedBox(height: AppSpacing.space4),
      ],
    ];
    return Scaffold(
      backgroundColor: context.tokens.page,
      appBar: AppBar(title: const Text('Institution email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.space6),
            children: [
              const Text(
                'Connect the mailbox that sends this institution’s emails. Replies arrive in that mailbox; read and reply there.',
              ),
              const SizedBox(height: AppSpacing.space4),
              if (_busy) ...[
                Semantics(
                  liveRegion: true,
                  label: 'Working',
                  child: const LinearProgressIndicator(),
                ),
                const SizedBox(height: AppSpacing.space4),
              ],
              if (!_feedbackAtForm) ...feedback,
              Text(
                configured
                    ? 'Mailbox: ${_mailbox!['from_email']} - ${mailboxStatusLabel(status)}'
                    : 'No institution mailbox connected.',
              ),
              const SizedBox(height: AppSpacing.space4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton(
                  label: 'Refresh settings',
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : _refresh,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              if (_jobId != null)
                JobProgress(
                  key: ValueKey(_jobId),
                  jobId: _jobId!,
                  load: (cancel) async =>
                      (await widget.dio.get<Map<String, dynamic>>(
                        '/api/workflow-jobs/$_jobId',
                        cancelToken: cancel,
                      )).data!,
                  onFinished: (result) {
                    if (mounted) {
                      setState(() {
                        _jobId = null;
                        _message = result['status'] == 'completed'
                            ? 'Connection verified. You can now enable sending.'
                            : 'Verification stopped. Check credentials, then verify again.';
                      });
                      _refresh();
                    }
                  },
                ),
              if (configured)
                Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  children: [
                    AppButton(
                      label: 'Verify connection',
                      onPressed: _busy || _jobId != null
                          ? null
                          : () => _post(
                              '$_base/${_mailbox!['id']}/verify',
                              null,
                              verification: true,
                            ),
                    ),
                    if (status == 'verified')
                      AppButton(
                        label: 'Enable sending',
                        onPressed: _busy ? null : () => _action('enable'),
                      ),
                    if (status == 'enabled')
                      AppButton(
                        label: 'Pause sending',
                        onPressed: _busy ? null : () => _action('pause'),
                      ),
                    AppButton(
                      label: 'Disconnect',
                      variant: AppButtonVariant.secondary,
                      onPressed: _busy ? null : () => _action('disconnect'),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.space6),
              const Text(
                'Saving new credentials replaces the connection and requires verification again.',
              ),
              const SizedBox(height: AppSpacing.space4),
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.space4,
                  children: [
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 100,
                      decoration: appFormDecoration(
                        context,
                        label: 'Sender name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter the institution name.'
                          : null,
                    ),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      maxLength: 254,
                      keyboardType: TextInputType.emailAddress,
                      decoration: appFormDecoration(
                        context,
                        label: 'Mailbox email',
                      ),
                      validator: (value) =>
                          value == null ||
                              !RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(value.trim())
                          ? 'Enter the complete email address.'
                          : null,
                    ),
                    TextFormField(
                      controller: _host,
                      enabled: !_busy,
                      maxLength: 253,
                      decoration: appFormDecoration(
                        context,
                        label: 'Outgoing SMTP host',
                        helper:
                            'Your provider must be approved by the server operator.',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter your outgoing SMTP host.'
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use TLS port 465'),
                      subtitle: const Text(
                        'Off uses STARTTLS port 587. Gmail normally uses 587.',
                      ),
                      value: _ssl,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _ssl = value),
                    ),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      maxLength: 1024,
                      decoration: appFormDecoration(
                        context,
                        label: 'App password / SMTP password',
                        helper:
                            'Password is never shown again. Do not use your normal Gmail login password.',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter the mailbox app password.'
                          : null,
                    ),
                    if (_feedbackAtForm) ...feedback,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: AppButton(
                        label: 'Save mailbox',
                        onPressed: _busy ? null : _save,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/widgets/auth_layout.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../data/mfa_repository.dart';

/// Two-factor sign-in (ADR-010), shown after the password step whenever the
/// server reports this session as restricted. Owners, institution admins and
/// campus admins must enrol; anyone who has enrolled must verify per device.
///
/// The backend enforces the restriction on every request. This screen only
/// lets the user complete it — it grants nothing by itself.
class MfaScreen extends StatefulWidget {
  const MfaScreen({
    required this.repository,
    required this.onVerified,
    required this.onSignOut,
    this.optionalEnrolment = false,
    super.key,
  });

  final MfaRepository repository;
  final VoidCallback onVerified;
  final Future<void> Function() onSignOut;

  /// Opened from More by a user whose role does not require MFA: enrol even
  /// though the session is not restricted, and never offer sign-out here.
  final bool optionalEnrolment;

  @override
  State<MfaScreen> createState() => MfaScreenState();
}

enum _Stage { loading, enrol, recoveryCodes, verify, alreadyEnabled, failed }

class MfaScreenState extends State<MfaScreen> {
  _Stage _stage = _Stage.loading;
  MfaEnrollment? _enrollment;
  List<String> _recoveryCodes = const [];
  String _code = '';
  bool _useRecoveryCode = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    final result = await widget.repository.status();
    if (!mounted) return;
    final status = result.status;
    if (status == null) {
      setState(() {
        _stage = _Stage.failed;
        _error =
            result.failure?.message ?? 'Could not check two-factor status.';
      });
      return;
    }
    if (widget.optionalEnrolment && status.enrolled) {
      setState(() => _stage = _Stage.alreadyEnabled);
      return;
    }
    if (!status.pending && !widget.optionalEnrolment) {
      widget.onVerified();
      return;
    }
    if (status.enrolled) {
      setState(() => _stage = _Stage.verify);
      return;
    }
    final begun = await widget.repository.beginEnrollment();
    if (!mounted) return;
    setState(() {
      _enrollment = begun.enrollment;
      _stage = begun.enrollment == null ? _Stage.failed : _Stage.enrol;
      _error = begun.failure?.message;
    });
  }

  Future<void> submit() async {
    if (_submitting || _code.trim().isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    if (_stage == _Stage.enrol) {
      final result = await widget.repository.confirmEnrollment(_code);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _code = '';
        if (result.recoveryCodes != null) {
          _recoveryCodes = result.recoveryCodes!;
          _stage = _Stage.recoveryCodes;
        } else {
          _error = result.failure?.message ?? 'That code was not accepted.';
        }
      });
      return;
    }
    final failure = _useRecoveryCode
        ? await widget.repository.verify(recoveryCode: _code)
        : await widget.repository.verify(code: _code);
    if (!mounted) return;
    if (failure == null) {
      widget.onVerified();
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure.message ?? 'That code was not accepted.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final children = <Widget>[];
    void heading(String title, String body) {
      children
        ..add(
          Text(
            title,
            style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space3))
        ..add(
          Text(
            body,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space6));
    }

    if (_error != null) {
      children
        ..add(InlineAlert(tone: InlineAlertTone.danger, message: _error!))
        ..add(const SizedBox(height: AppSpacing.space6));
    }

    switch (_stage) {
      case _Stage.loading:
        children.add(const Center(child: CircularProgressIndicator()));
      case _Stage.alreadyEnabled:
        heading(
          'Two-factor authentication',
          'Two-factor authentication is already enabled for your account.',
        );
        children.add(
          AppButton(
            label: 'Done',
            fullWidth: true,
            onPressed: widget.onVerified,
          ),
        );
      case _Stage.failed:
        heading(
          'Two-factor authentication',
          'Two-factor sign-in could not be started.',
        );
        children.add(
          AppButton(label: 'Try again', fullWidth: true, onPressed: _load),
        );
      case _Stage.enrol:
        heading(
          'Set up two-factor authentication',
          '${widget.optionalEnrolment ? '' : 'Your role requires an authenticator app. '}'
              'Add this key to Google Authenticator, Microsoft Authenticator or a '
              'similar app, then enter the 6-digit code it shows.',
        );
        children
          ..add(
            SelectableText(
              _enrollment!.secret,
              key: const Key('mfa-secret'),
              style: AppTypography.screenTitle.copyWith(
                color: t.textPrimary,
                letterSpacing: 2,
              ),
            ),
          )
          ..add(const SizedBox(height: AppSpacing.space3))
          ..add(
            AppButton(
              label: 'Copy setup link',
              variant: AppButtonVariant.secondary,
              onPressed: () => Clipboard.setData(
                ClipboardData(text: _enrollment!.otpauthUrl),
              ),
            ),
          )
          ..add(const SizedBox(height: AppSpacing.space6))
          ..addAll(_codeField('Authenticator code'));
      case _Stage.recoveryCodes:
        heading(
          'Save your recovery codes',
          'Each code works once if you lose your authenticator. They will not '
              'be shown again. Store them somewhere safe.',
        );
        children
          ..add(
            SelectableText(
              _recoveryCodes.join('\n'),
              key: const Key('mfa-recovery-codes'),
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          )
          ..add(const SizedBox(height: AppSpacing.space6))
          ..add(
            AppButton(
              label: 'I have saved them',
              fullWidth: true,
              onPressed: widget.onVerified,
            ),
          );
      case _Stage.verify:
        heading(
          'Two-factor verification',
          _useRecoveryCode
              ? 'Enter one of your unused recovery codes.'
              : 'Enter the 6-digit code from your authenticator app.',
        );
        children
          ..addAll(
            _codeField(
              _useRecoveryCode ? 'Recovery code' : 'Authenticator code',
            ),
          )
          ..add(const SizedBox(height: AppSpacing.space3))
          ..add(
            AppButton(
              label: _useRecoveryCode
                  ? 'Use authenticator code'
                  : 'Use a recovery code',
              variant: AppButtonVariant.ghost,
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      _useRecoveryCode = !_useRecoveryCode;
                      _code = '';
                      _error = null;
                    }),
            ),
          );
    }

    if (_stage != _Stage.recoveryCodes && !widget.optionalEnrolment) {
      children
        ..add(const SizedBox(height: AppSpacing.space6))
        ..add(
          AppButton(
            label: 'Sign out',
            variant: AppButtonVariant.ghost,
            onPressed: _submitting ? null : widget.onSignOut,
          ),
        );
    }

    return Scaffold(
      backgroundColor: t.page,
      // M1: the same sign-in frame as login, so the journey reads as one product.
      body: SafeArea(
        child: AuthLayout(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  List<Widget> _codeField(String label) => [
    AppTextField(
      key: const Key('mfa-code'),
      label: label,
      required: true,
      value: _code,
      autofocus: true,
      state: _submitting
          ? AppTextFieldState.disabled
          : AppTextFieldState.normal,
      onChanged: (v) => setState(() => _code = v),
      onSubmitted: (_) => submit(),
    ),
    const SizedBox(height: AppSpacing.space6),
    AppButton(
      label: _submitting ? 'Checking…' : 'Verify',
      fullWidth: true,
      onPressed: _submitting || _code.trim().isEmpty ? null : submit,
    ),
  ];
}

/// Prompts for a fresh authenticator code before a sensitive finance action.
/// Returns true only once the server accepted the code.
Future<bool> showStepUpDialog(
  BuildContext context,
  MfaRepository repository,
  String reason,
) async {
  if (reason == 'MFA_ENROLLMENT_REQUIRED') {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Two-factor authentication required'),
        content: const Text(
          'This action needs two-factor authentication. Set it up from More → '
          'Two-factor authentication, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _StepUpDialog(repository: repository),
  );
  return accepted ?? false;
}

class _StepUpDialog extends StatefulWidget {
  const _StepUpDialog({required this.repository});
  final MfaRepository repository;

  @override
  State<_StepUpDialog> createState() => _StepUpDialogState();
}

class _StepUpDialogState extends State<_StepUpDialog> {
  String _code = '';
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting || _code.trim().isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final failure = await widget.repository.stepUp(_code);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure.message ?? 'That code was not accepted.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm it is you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter the 6-digit code from your authenticator app. '
            'It stays valid on this device for five minutes.',
          ),
          const SizedBox(height: AppSpacing.space6),
          if (_error != null) ...[
            InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            const SizedBox(height: AppSpacing.space3),
          ],
          AppTextField(
            key: const Key('step-up-code'),
            label: 'Authenticator code',
            required: true,
            value: _code,
            autofocus: true,
            state: _submitting
                ? AppTextFieldState.disabled
                : AppTextFieldState.normal,
            onChanged: (v) => setState(() => _code = v),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submitting || _code.trim().isEmpty ? null : _submit,
          child: Text(_submitting ? 'Checking…' : 'Confirm'),
        ),
      ],
    );
  }
}

/// Makes the two-factor repository reachable from More without threading it
/// through every role's destination builder.
class MfaScope extends InheritedWidget {
  const MfaScope({required this.repository, required super.child, super.key});

  final MfaRepository repository;

  static MfaRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MfaScope>()?.repository;

  @override
  bool updateShouldNotify(MfaScope oldWidget) =>
      repository != oldWidget.repository;
}

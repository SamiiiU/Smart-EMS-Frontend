import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../data/auth_repository.dart';

/// Forced password change, shown before the shell when the login response
/// carries `forcePasswordChange: true` (a provisioned or admin-reset
/// account).
///
/// Succeeding revokes EVERY session including this one, so this screen ends
/// at the login screen, not the dashboard. Telling the user that up front is
/// the difference between a deliberate step and an app that appears to log
/// them out at random.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    required this.repository,
    required this.onChanged,
    super.key,
  });

  final AuthRepository repository;

  /// Called after a successful change AND after local tokens are cleared.
  /// The caller returns to login.
  final VoidCallback onChanged;

  @override
  State<ChangePasswordScreen> createState() => ChangePasswordScreenState();
}

class ChangePasswordScreenState extends State<ChangePasswordScreen> {
  String _current = '';
  String _next = '';
  String _confirm = '';
  bool _submitting = false;
  String? _error;

  bool get _canSubmit =>
      !_submitting &&
      _current.isNotEmpty &&
      _next.isNotEmpty &&
      _confirm.isNotEmpty;

  Future<void> submit() async {
    if (!_canSubmit) return;

    // Checked locally because the backend has no confirm field — a typo
    // here would otherwise lock the user out of an account they just set.
    if (_next != _confirm) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final failure = await widget.repository.changePassword(
      currentPassword: _current,
      newPassword: _next,
    );

    if (!mounted) return;

    if (failure == null) {
      widget.onChanged();
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure.message ?? 'Could not change your password.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.space8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizing.authFormMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set a new password',
                    style: AppTypography.screenTitle
                        .copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    'Your account needs a new password before you can '
                    'continue.',
                    style: AppTypography.bodyAdminMeta
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  // Stated BEFORE the action, not after: being returned to
                  // the login screen is expected here, not a failure.
                  const InlineAlert(
                    tone: InlineAlertTone.info,
                    message: 'Changing your password signs you out '
                        'everywhere. You will sign in again with the new one.',
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  if (_error != null) ...[
                    InlineAlert(
                      tone: InlineAlertTone.danger,
                      message: _error!,
                    ),
                    const SizedBox(height: AppSpacing.space6),
                  ],
                  AppTextField(
                    label: 'Current password',
                    value: _current,
                    obscure: true,
                    state: _submitting
                        ? AppTextFieldState.disabled
                        : AppTextFieldState.normal,
                    onChanged: (v) => setState(() => _current = v),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  AppTextField(
                    label: 'New password',
                    value: _next,
                    obscure: true,
                    state: _submitting
                        ? AppTextFieldState.disabled
                        : AppTextFieldState.normal,
                    onChanged: (v) => setState(() => _next = v),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  AppTextField(
                    label: 'Confirm new password',
                    value: _confirm,
                    obscure: true,
                    state: _submitting
                        ? AppTextFieldState.disabled
                        : AppTextFieldState.normal,
                    onChanged: (v) => setState(() => _confirm = v),
                  ),
                  const SizedBox(height: AppSpacing.space8),
                  AppButton(
                    label: _submitting ? 'Saving…' : 'Save',
                    fullWidth: true,
                    onPressed: _canSubmit ? submit : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

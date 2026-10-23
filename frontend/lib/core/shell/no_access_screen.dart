import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';
import '../widgets/app_button.dart';

/// Shown when the signed-in account holds no role this app can serve, most
/// often because an administrator removed the last grant mid-session
/// (hard-QA BUG-QA-21: the Pixel showed "No access — built in a later task",
/// a developer placeholder with no way forward).
///
/// It explains in plain words, lets the person check again (the grant may
/// have been restored) and sign out. No data is loaded here.
class NoAccessScreen extends StatefulWidget {
  const NoAccessScreen({required this.onSignOut, this.onCheckAgain, super.key});

  final Future<void> Function() onSignOut;
  final Future<void> Function()? onCheckAgain;

  @override
  State<NoAccessScreen> createState() => _NoAccessScreenState();
}

class _NoAccessScreenState extends State<NoAccessScreen> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await widget.onCheckAgain?.call();
    } on Object {
      // Still no access, or offline: stay here.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space8),
          child: Column(
            key: const Key('no-access'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline, size: 48, color: t.textSecondary),
              const SizedBox(height: AppSpacing.space5),
              Semantics(
                header: true,
                child: Text(
                  'Your account has no access here yet',
                  textAlign: TextAlign.center,
                  style: AppTypography.screenTitle.copyWith(
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'You are signed in, but no role is currently assigned to your account in this '
                'institution. If you need access, ask your institution’s administrator, then '
                'check again.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyTeacher.copyWith(
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              if (widget.onCheckAgain != null) ...[
                AppButton(
                  key: const Key('no-access-check'),
                  label: _checking ? 'Checking…' : 'Check again',
                  fullWidth: true,
                  onPressed: _checking ? null : _check,
                ),
                const SizedBox(height: AppSpacing.space3),
              ],
              AppButton(
                key: const Key('no-access-sign-out'),
                label: 'Sign out',
                variant: AppButtonVariant.secondary,
                fullWidth: true,
                onPressed: widget.onSignOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

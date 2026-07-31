import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/scales.dart';
import '../../theme/typography.dart';
import '../app_button.dart';
import 'empty_state.dart';

/// A load failed and there is no cached data to fall back on.
///
/// THE MESSAGE IS THE BACKEND'S, VERBATIM, when there is one. Backend messages
/// name the actual problem and often the next step — "Attendance for this date
/// is locked" tells the user what to do; "Something went wrong" discards that
/// and makes the product look broken rather than constrained.
///
/// THE RETRY PATH IS ENUMERATED (D-11). A retry button that visibly does
/// nothing is worse than one that explains, so the component tracks its own
/// attempts: after the SECOND consecutive failure it stops presenting the same
/// face and says that retrying is not working, suggesting the connection as the
/// likely cause. The attempt count lives here rather than in the caller,
/// because every caller would otherwise have to remember to implement it.
class ErrorState extends StatefulWidget {
  const ErrorState({
    required this.onRetry,
    this.message,
    this.title = 'Could not load this',
    super.key,
  });

  /// Called on each retry. The caller re-runs the load; if it fails again the
  /// caller rebuilds this widget, and [ErrorState] counts that itself.
  final VoidCallback onRetry;

  /// The backend's message. Shown verbatim. Null when there genuinely is none,
  /// in which case a neutral fallback is used.
  final String? message;

  final String title;

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  /// How many times the user has pressed retry on THIS error surface.
  int _attempts = 0;

  /// True once retrying has visibly stopped helping.
  bool get _escalated => _attempts >= 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return StateFrame(
      icon: Icons.error_outline,
      iconColour: t.danger,
      title: widget.title,
      message: widget.message ?? 'The request did not complete.',
      secondary: _escalated
          ? _EscalationNotice(attempts: _attempts)
          : null,
      action: AppButton(
        // The label changes too, so the second press does not look identical
        // to the first even before the notice appears.
        label: _attempts == 0 ? 'Retry' : 'Try again',
        onPressed: () {
          setState(() => _attempts++);
          widget.onRetry();
        },
      ),
    );
  }
}

/// Shown after the second consecutive failure. Says plainly that retrying is
/// not working, rather than letting the user press a button that keeps
/// producing the same screen.
class _EscalationNotice extends StatelessWidget {
  const _EscalationNotice({required this.attempts});

  final int attempts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        'Retrying is not working. Check your internet connection, then try '
        'again.',
        textAlign: TextAlign.center,
        style: AppTypography.bodyAdminMeta.copyWith(
          color: t.warningTextOnBg,
        ),
      ),
    );
  }
}

/// The device is offline AND there is no cached data to show.
///
/// NOT AN ERROR, and it must not look like one — no danger colour, no failure
/// icon. Offline is a MODE, not a fault, and in the institutions this product
/// serves it is routine rather than exceptional. Styling it as a failure trains
/// users to distrust a normal condition.
///
/// NO RETRY BUTTON: retrying does not create a network. The content loads when
/// the connection returns, and saying so is more useful than a button that
/// cannot work.
class OfflineState extends StatelessWidget {
  const OfflineState({
    this.title = 'You are offline',
    this.message =
        'This will load as soon as the connection comes back. Nothing has been '
            'lost.',
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StateFrame(
      icon: Icons.cloud_off_outlined,
      // Deliberately NOT t.danger — see the class doc and the styling test.
      iconColour: t.textSecondary,
      title: title,
      message: message,
      // No action. Intentional.
    );
  }
}

/// `/api/staff/me` or `/api/students/me` returned 404.
///
/// NOT AN ERROR either. The login exists but was never linked to a person
/// record — the orphan case D-17 exists to prevent, produced by a wizard that
/// committed step 1 and then stopped. There is no user list endpoint, so the
/// user cannot see or fix this themselves.
///
/// So it explains the situation and directs them to their school
/// administrator. NO RETRY: the record will not appear because they pressed a
/// button, and offering one implies they can fix it.
class UnlinkedProfileState extends StatelessWidget {
  const UnlinkedProfileState({
    this.title = 'Your profile is not set up yet',
    this.message =
        'Your login works, but it has not been linked to a staff or student '
            'record yet. Please ask your school administrator to finish setting '
            'up your profile.',
    super.key,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StateFrame(
      icon: Icons.person_outline,
      // Informational, not a failure.
      iconColour: t.info,
      title: title,
      message: message,
      // No action — the user cannot resolve this.
    );
  }
}

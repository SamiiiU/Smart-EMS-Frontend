import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';
import 'app_button.dart';

/// The one confirmation dialog (overhaul M1).
///
/// Before this, 13 screens each built an `AlertDialog` with two
/// `TextButton`s, so the irreversible "Approve payment" looked exactly like
/// "Discard draft". The rules this enforces:
///
/// - The confirm button names the action ("Approve", "Remove role"), never
///   "OK" — the user should not have to reread the title to know what it does.
/// - Cancel is always present, always first, and always the safe default:
///   dismissing the dialog (back, Esc, tapping outside) returns `false`.
/// - [irreversible] adds a visible warning, because "this cannot be undone"
///   buried in body text is easy to skim past.
///
/// Returns true only when the user explicitly confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool irreversible = false,
  Key? confirmKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      irreversible: irreversible,
      confirmKey: confirmKey,
    ),
  );
  return result ?? false;
}

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.irreversible = false,
    this.confirmKey,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool irreversible;

  /// Overrides the confirm button's key (default `confirm-ok`).
  final Key? confirmKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl2),
      ),
      // Readable line length on desktop; Material already caps phone width.
      constraints: const BoxConstraints(maxWidth: 440),
      title: Row(
        children: [
          if (irreversible) ...[
            Icon(Icons.warning_amber_rounded, color: t.danger),
            const SizedBox(width: AppSpacing.space3),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTypography.cardHeading
                  .copyWith(color: irreversible ? t.danger : t.textPrimary),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
          ),
          if (irreversible) ...[
            const SizedBox(height: AppSpacing.space4),
            Text(
              'This cannot be undone.',
              style: AppTypography.fieldLabel.copyWith(color: t.danger),
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.space5, 0, AppSpacing.space5, AppSpacing.space5),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            AppButton(
              key: const Key('confirm-cancel'),
              label: cancelLabel,
              variant: AppButtonVariant.secondary,
              // Focus starts INSIDE the dialog, on the safe choice: on web the
              // page behind otherwise kept DOM focus (Tab and Space reached the
              // row actions under the barrier, Escape did nothing), and Enter
              // must never confirm an irreversible action by default.
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton(
              key: confirmKey ?? const Key('confirm-ok'),
              label: confirmLabel,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ],
    );
  }
}

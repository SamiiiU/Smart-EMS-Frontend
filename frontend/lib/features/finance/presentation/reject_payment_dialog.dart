import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../domain/money.dart';

/// Shows the shared reject confirmation; resolves to the trimmed reason, or
/// null when cancelled (nothing is sent then).
Future<String?> showRejectPaymentDialog(
  BuildContext context, {
  required Money amount,
  required String studentName,
}) => showDialog<String>(
  context: context,
  builder: (_) => RejectPaymentDialog(amount: amount, studentName: studentName),
);

/// Reject confirmation with a REQUIRED reason. Returns the trimmed reason, or
/// null when cancelled (Cancel, Escape or tapping outside). Focus starts in the
/// reason field, inside the dialog.
class RejectPaymentDialog extends StatefulWidget {
  const RejectPaymentDialog({
    required this.amount,
    required this.studentName,
    super.key,
  });

  final Money amount;
  final String studentName;

  /// A meaningful reason: at least this many non-space characters.
  static const minLength = 3;

  @override
  State<RejectPaymentDialog> createState() => _RejectPaymentDialogState();
}

class _RejectPaymentDialogState extends State<RejectPaymentDialog> {
  String _reason = '';

  bool get _valid => _reason.trim().length >= RejectPaymentDialog.minLength;

  void _submit() {
    if (_valid) Navigator.of(context).pop(_reason.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: const Text('Reject this payment?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.amount.format()} from ${widget.studentName} will not be counted against '
              'the invoice, and the family will be told the payment could not be '
              'verified. A rejected payment cannot be approved later.',
            ),
            const SizedBox(height: AppSpacing.space5),
            AppTextField(
              key: const Key('reject-reason'),
              label: 'Reason',
              required: true,
              autofocus: true,
              // Controlled field: without `value`, each rebuild resynced the text to '' (DEF-13).
              value: _reason,
              placeholder: 'e.g. Bank challan not found in statement',
              onChanged: (v) => setState(() => _reason = v),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Required. Saved with the payment record.',
              style: AppTypography.caption.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'This cannot be undone.',
              style: AppTypography.fieldLabel.copyWith(color: t.danger),
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
              key: const Key('reject-cancel'),
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              key: const Key('reject-confirm'),
              label: 'Reject',
              onPressed: _valid ? _submit : null,
            ),
          ],
        ),
      ],
    );
  }
}

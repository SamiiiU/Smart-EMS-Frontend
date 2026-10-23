import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/states/empty_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/finance_repository.dart';
import '../domain/money.dart';
import '../../setup/presentation/setup_scaffold.dart';

/// Server-authorized, independent discount requests. Never adjusts an invoice locally.
class DiscountRequestsScreen extends StatefulWidget {
  const DiscountRequestsScreen({
    required this.repository,
    required this.invoiceId,
    super.key,
  });
  final FinanceRepository repository;
  final String invoiceId;
  @override
  State<DiscountRequestsScreen> createState() => _DiscountRequestsScreenState();
}

/// Human wording for server statuses; unknown values are shown, never hidden.
String discountStatusLabel(Object? status) => switch (status) {
  'pending_approval' => 'Awaiting approval',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  null => 'Unknown',
  _ => status.toString().replaceAll('_', ' '),
};

/// "PKR 100.00" for amounts, "10.00%" for percentages; raw text if unparseable.
String discountValueLabel(Map<String, dynamic> row) {
  final amount = row['requested_amount'];
  if (amount != null) {
    return Money.tryParse('$amount')?.format() ?? 'PKR $amount';
  }
  return '${row['requested_percentage']}%';
}

class _DiscountRequestsScreenState extends State<DiscountRequestsScreen> {
  final _value = TextEditingController();
  final _reason = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  bool _percentage = false, _busy = false, _recovering = false;
  String? _error, _notice, _recordedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _rows = null;
      _error = null;
    });
    try {
      final rows = await widget.repository.loadDiscountRequests(
        widget.invoiceId,
      );
      final intent = await widget.repository.pendingPaymentIntent(
        'discount:${widget.invoiceId}',
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _recovering = intent != null;
        if (intent != null) {
          _value.text = intent.amount;
          _reason.text = intent.reference ?? '';
          _percentage = intent.source == 'DISCOUNT_PERCENTAGE';
          _recordedId = intent.paymentId;
          _notice = intent.paymentId == null
              ? 'An earlier request needs reconciliation. Retry its original details.'
              : 'Request recorded. Its current decision appears below.';
        }
      });
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is LoadFailure
              ? e.message ?? 'Discount requests unavailable.'
              : 'Recovery storage unavailable. No request was sent.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(_value.text.trim())) {
      setState(
        () => _error =
            'Enter a nonnegative value with at most two decimal places.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.repository.requestDiscount(
        invoiceId: widget.invoiceId,
        value: _value.text.trim(),
        percentage: _percentage,
        description: _reason.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _recordedId = id;
        _notice =
            'Request recorded. Invoice totals change only after independent approval.';
      });
      await _load();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _rows = null;
          _recovering = true;
          _error = e is LoadFailure
              ? e.message ??
                    'Outcome unconfirmed. Refresh to recover the original request.'
              : 'Request not confirmed. Refresh to check recovery storage.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (_) => DiscountDecisionDialog(
        approve: approve,
        value: discountValueLabel(row),
      ),
    );
    // null = cancelled (Cancel, Escape, tap outside): nothing is sent.
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.decideDiscount(
        row['id'] as String,
        approve: approve,
        reason: approve ? null : reason,
      );
      if (mounted) await _load();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _rows = null;
          _error = e is LoadFailure
              ? e.message ?? 'Decision not confirmed. Refresh before retrying.'
              : 'Decision not confirmed. Refresh before retrying.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startNew() async {
    await widget.repository.finishPaymentIntent(
      'discount:${widget.invoiceId}',
      _recordedId!,
    );
    if (mounted) {
      setState(() {
        _recordedId = null;
        _recovering = false;
        _value.clear();
        _reason.clear();
        _notice = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const gap = SizedBox(height: AppSpacing.space5);
    final locked = _busy || _recovering;
    return SetupScaffold(
      title: 'Discount requests',
      note: const Text(
        'Every discount needs a second authorized approver. Pending requests do not '
        'change totals, and a discount cannot reduce the bill below money already collected.',
      ),
      children: [
        if (_busy) ...[
          Semantics(
            liveRegion: true,
            label: 'Loading discount requests',
            child: const LinearProgressIndicator(),
          ),
          gap,
        ],
        if (_error != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          gap,
        ],
        if (_notice != null) ...[
          InlineAlert(
            tone: _recovering && _recordedId == null
                ? InlineAlertTone.warning
                : InlineAlertTone.success,
            message: _notice!,
          ),
          gap,
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: 'Refresh requests',
            icon: Icons.refresh,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _busy ? null : _load,
          ),
        ),
        gap,
        if (_rows != null) ...[
          if (_recordedId == null)
            SectionCard(
              title: _recovering ? 'Retry the earlier request' : 'New request',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Own Material so ink/selection paints above SectionCard's DecoratedBox.
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Use percentage',
                        style: AppTypography.bodyTeacher,
                      ),
                      subtitle: Text(
                        _percentage
                            ? 'Value is a percentage of the invoice'
                            : 'Value is an amount in PKR',
                        style: AppTypography.caption.copyWith(
                          color: t.textSecondary,
                        ),
                      ),
                      value: _percentage,
                      onChanged: locked
                          ? null
                          : (value) => setState(() => _percentage = value),
                    ),
                  ),
                  gap,
                  AppTextField(
                    key: const Key('discount-value'),
                    label: _percentage ? 'Percentage' : 'Amount (PKR)',
                    required: true,
                    value: _value.text,
                    placeholder: _percentage ? 'e.g. 10' : 'e.g. 500.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    state: locked
                        ? AppTextFieldState.disabled
                        : AppTextFieldState.normal,
                    onChanged: (v) => _value.text = v,
                  ),
                  gap,
                  AppTextField(
                    key: const Key('discount-reason'),
                    label: 'Discount reason',
                    value: _reason.text,
                    placeholder:
                        'e.g. Sibling concession approved by principal',
                    state: locked
                        ? AppTextFieldState.disabled
                        : AppTextFieldState.normal,
                    onChanged: (v) => _reason.text = v,
                  ),
                  gap,
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppButton(
                      key: const Key('discount-submit'),
                      label: _recovering
                          ? 'Retry original request'
                          : 'Request discount',
                      onPressed: _busy ? null : _submit,
                    ),
                  ),
                ],
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: 'New discount request',
                icon: Icons.add,
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : _startNew,
              ),
            ),
          gap,
          if (_rows!.isEmpty)
            const EmptyState(
              icon: Icons.percent,
              title: 'No discount requests',
              message:
                  'Requests for this invoice will appear here with their decision.',
            ),
          for (final row in _rows!) ...[
            _DiscountRow(
              row: row,
              busy: _busy,
              onApprove: () => _decide(row, true),
              onReject: () => _decide(row, false),
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
        ],
      ],
    );
  }
}

class _DiscountRow extends StatelessWidget {
  const _DiscountRow({
    required this.row,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });
  final Map<String, dynamic> row;
  final bool busy;
  final VoidCallback onApprove, onReject;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = discountStatusLabel(row['status']);
    final description = row['description'] as String? ?? '';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Wrap(
              spacing: AppSpacing.space4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(discountValueLabel(row), style: AppTypography.cardHeading),
                Text(
                  'Status: $status',
                  style: AppTypography.fieldLabel.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(description, style: AppTypography.bodyTeacher),
          ],
          if (row['decision_reason'] != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Decision note: ${row['decision_reason']}',
              style: AppTypography.caption.copyWith(color: t.textSecondary),
            ),
          ],
          if (row['canDecide'] == true) ...[
            const SizedBox(height: AppSpacing.space5),
            Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space4,
              children: [
                AppButton(
                  label: 'Approve discount',
                  semanticsLabel:
                      'Approve discount of ${discountValueLabel(row)}',
                  onPressed: busy ? null : onApprove,
                ),
                AppButton(
                  label: 'Reject discount',
                  semanticsLabel:
                      'Reject discount of ${discountValueLabel(row)}',
                  variant: AppButtonVariant.secondary,
                  onPressed: busy ? null : onReject,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Approve/reject confirmation. Resolves to '' (approve) or the trimmed rejection
/// reason, or null when cancelled. Rejection requires a non-blank reason (unchanged rule).
class DiscountDecisionDialog extends StatefulWidget {
  const DiscountDecisionDialog({
    required this.approve,
    required this.value,
    super.key,
  });
  final bool approve;
  final String value;
  @override
  State<DiscountDecisionDialog> createState() => _DiscountDecisionDialogState();
}

class _DiscountDecisionDialogState extends State<DiscountDecisionDialog> {
  String _reason = '';
  bool _attempted = false;

  void _confirm() {
    if (widget.approve) {
      Navigator.of(context).pop('');
    } else if (_reason.trim().isNotEmpty) {
      Navigator.of(context).pop(_reason.trim());
    } else {
      setState(() => _attempted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final missing = !widget.approve && _attempted && _reason.trim().isEmpty;
    return AlertDialog(
      title: Text(
        widget.approve
            ? 'Approve ${widget.value} discount?'
            : 'Reject ${widget.value} discount?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.approve
                  ? 'The server rechecks the current balance. You cannot approve your own request, '
                        'and fresh MFA verification is required.'
                  : 'A rejection leaves invoice totals unchanged.',
            ),
            if (!widget.approve) ...[
              const SizedBox(height: AppSpacing.space5),
              AppTextField(
                key: const Key('discount-reject-reason'),
                label: 'Rejection reason',
                required: true,
                autofocus: true,
                // Controlled field: without `value`, each rebuild resynced the text to '' and only the
                // last typed character survived (found by browser typing, DEF-12).
                value: _reason,
                state: missing
                    ? AppTextFieldState.error
                    : AppTextFieldState.normal,
                errorText: missing ? 'Enter a reason to reject.' : null,
                onChanged: (v) => setState(() => _reason = v),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Required. Saved with the decision.',
                style: AppTypography.caption.copyWith(color: t.textSecondary),
              ),
            ],
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
              key: const Key('discount-decision-cancel'),
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              key: const Key('discount-decision-confirm'),
              label: widget.approve ? 'Approve' : 'Reject',
              onPressed: _confirm,
            ),
          ],
        ),
      ],
    );
  }
}

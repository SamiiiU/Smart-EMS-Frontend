import 'package:flutter/material.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/finance_repository.dart';
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
    String reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve discount?' : 'Reject discount?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              approve
                  ? 'The server rechecks the current balance. You cannot approve your own request. Fresh MFA is required.'
                  : 'A rejection leaves invoice totals unchanged.',
            ),
            if (!approve)
              TextField(
                onChanged: (value) => reason = value,
                decoration: const InputDecoration(
                  labelText: 'Rejection reason',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (approve || reason.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    final explanation = reason.trim();
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.decideDiscount(
        row['id'] as String,
        approve: approve,
        reason: approve ? null : explanation,
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

  @override
  Widget build(BuildContext context) => SetupScaffold(
    title: 'Discount requests',
    children: [
      const Text(
        'Every discount requires another authorized approver. Pending requests do not change totals. Discounts cannot reduce the bill below money already collected.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, semanticsLabel: _error),
      if (_notice != null) Text(_notice!),
      TextButton(
        onPressed: _busy ? null : _load,
        child: const Text('Refresh requests'),
      ),
      if (_rows != null) ...[
        if (_recordedId == null) ...[
          SwitchListTile(
            title: const Text('Use percentage'),
            value: _percentage,
            onChanged: _busy || _recovering
                ? null
                : (value) => setState(() => _percentage = value),
          ),
          TextField(
            controller: _value,
            enabled: !_busy && !_recovering,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _percentage ? 'Percentage' : 'Amount (PKR)',
            ),
          ),
          TextField(
            controller: _reason,
            enabled: !_busy && !_recovering,
            decoration: const InputDecoration(labelText: 'Discount reason'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _recovering ? 'Retry original request' : 'Request discount',
            ),
          ),
        ] else
          TextButton(
            onPressed: _busy
                ? null
                : () async {
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
                  },
            child: const Text('New discount request'),
          ),
        if (_rows!.isEmpty) const Text('No discount requests.'),
        for (final row in _rows!)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['requested_amount'] ?? row['requested_percentage']} ${row['requested_amount'] == null ? '%' : 'PKR'} - ${row['status']}',
                  ),
                  Text(row['description'] as String? ?? ''),
                  if (row['decision_reason'] != null)
                    Text(row['decision_reason'] as String),
                  if (row['canDecide'] == true)
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _decide(row, true),
                          child: const Text('Approve discount'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _decide(row, false),
                          child: const Text('Reject discount'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    ],
  );
}

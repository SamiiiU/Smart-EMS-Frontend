import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/ownership_repository.dart';
import '../../../core/widgets/page_header.dart';

/// ADR-007 ownership transfer (Option C). The current owner starts it; the
/// incoming owner completes it and chooses the former owner's access, which
/// defaults to NO ACCESS. Every step asks for a fresh authenticator code. The
/// server enforces who may do what; this screen only collects the choices.
class OwnershipTransferScreen extends StatefulWidget {
  const OwnershipTransferScreen({
    required this.repository,
    this.userId,
    super.key,
  });

  final OwnershipRepository repository;

  /// Signed-in account, to tell "I started this" from "this is for me".
  final String? userId;

  @override
  State<OwnershipTransferScreen> createState() =>
      _OwnershipTransferScreenState();
}

class _OwnershipTransferScreenState extends State<OwnershipTransferScreen> {
  bool _loading = true;
  String? _me;
  PendingTransfer? _pending;
  List<TransferCandidate> _candidates = const [];
  String? _target;
  FormerOwnerAccess _access = FormerOwnerAccess.none;
  String _code = '';
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _me = widget.userId ?? await widget.repository.myUserId();
    final pending = await widget.repository.pending();
    final candidates = pending.transfer == null
        ? await widget.repository.candidates()
        : null;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _pending = pending.transfer;
      _candidates = (candidates?.candidates ?? const [])
          .where((c) => c.userId != _me)
          .toList();
      _error = pending.failure?.message;
    });
  }

  Future<void> _run(
    Future<LoadFailure?> Function() action,
    String success,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _code = '';
      if (failure == null) {
        _done = success;
      } else {
        _error = failure.message ?? 'The request was refused.';
      }
    });
    if (failure == null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pending = _pending;
    final children = <Widget>[
      const PageHeader(title: 'Ownership transfer', padding: EdgeInsets.zero),
      const SizedBox(height: AppSpacing.space6),
      if (_done != null) ...[
        InlineAlert(tone: InlineAlertTone.success, message: _done!),
        const SizedBox(height: AppSpacing.space6),
      ],
      if (_error != null) ...[
        InlineAlert(tone: InlineAlertTone.danger, message: _error!),
        const SizedBox(height: AppSpacing.space6),
      ],
    ];

    Widget codeField() => AppTextField(
      key: const Key('ownership-code'),
      label: 'Authenticator code',
      required: true,
      value: _code,
      onChanged: (v) => setState(() => _code = v),
    );

    if (_loading) {
      children.add(const Center(child: CircularProgressIndicator()));
    } else if (pending != null && pending.targetUserId == _me) {
      children
        ..add(
          Text(
            'You have been asked to become the institution owner. Choose what the '
            'current owner keeps. They will be signed out everywhere either way.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space4))
        ..add(
          Semantics(
            label: 'What the current owner keeps',
            container: true,
            explicitChildNodes: true,
            child: RadioGroup<FormerOwnerAccess>(
              groupValue: _access,
              onChanged: (v) =>
                  setState(() => _access = v ?? FormerOwnerAccess.none),
              child: const Column(
                children: [
                  RadioListTile<FormerOwnerAccess>(
                    key: Key('access-none'),
                    value: FormerOwnerAccess.none,
                    title: Text('No institution access (recommended)'),
                  ),
                  RadioListTile<FormerOwnerAccess>(
                    key: Key('access-admin'),
                    value: FormerOwnerAccess.institutionAdmin,
                    title: Text('Institution Admin (no ownership powers)'),
                  ),
                ],
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space4))
        ..add(codeField())
        ..add(const SizedBox(height: AppSpacing.space6))
        ..add(
          AppButton(
            label: 'Accept ownership',
            fullWidth: true,
            onPressed: _busy || _code.trim().isEmpty
                ? null
                : () => _run(
                    () => widget.repository.accept(
                      transferId: pending.id,
                      access: _access,
                      code: _code,
                    ),
                    'You are now the institution owner.',
                  ),
          ),
        );
    } else if (pending != null) {
      children
        ..add(
          Text(
            'A transfer is waiting for the new owner to accept.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space6))
        ..add(
          AppButton(
            label: 'Cancel transfer',
            variant: AppButtonVariant.secondary,
            onPressed: _busy
                ? null
                : () => _run(
                    () => widget.repository.cancel(pending.id),
                    'Transfer cancelled.',
                  ),
          ),
        );
    } else {
      children
        ..add(
          Text(
            'Only the current owner can start a transfer. The new owner must have '
            'two-factor authentication and will choose what you keep (default: no access).',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space4))
        ..add(
          Semantics(
            label: 'New owner',
            hint: 'Required. Must have two-factor authentication.',
            child: DropdownButton<String>(
              key: const Key('ownership-target'),
              isExpanded: true,
              value: _target,
              hint: const Text('Choose the new owner'),
              items: [
                for (final c in _candidates)
                  DropdownMenuItem(value: c.userId, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _target = v),
            ),
          ),
        )
        ..add(const SizedBox(height: AppSpacing.space4))
        ..add(codeField())
        ..add(const SizedBox(height: AppSpacing.space6))
        ..add(
          AppButton(
            label: 'Start transfer',
            fullWidth: true,
            onPressed: _busy || _target == null || _code.trim().isEmpty
                ? null
                : () => _run(
                    () => widget.repository.initiate(
                      targetUserId: _target!,
                      code: _code,
                    ),
                    'Transfer started. The new owner must now accept it.',
                  ),
          ),
        );
    }

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          children: children,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/institution_admin_repository.dart';

/// ADR-007 / Doc 21: the institution Owner appoints and removes Institution
/// Admins. Each change needs a fresh authenticator code for that one person.
/// The appointee must already have a login and two-factor authentication; the
/// server checks every rule and refuses anyone but the Owner.
class InstitutionAdminsScreen extends StatefulWidget {
  const InstitutionAdminsScreen({required this.repository, super.key});

  final InstitutionAdminRepository repository;

  @override
  State<InstitutionAdminsScreen> createState() => InstitutionAdminsScreenState();
}

class InstitutionAdminsScreenState extends State<InstitutionAdminsScreen> {
  bool _loading = true;
  List<InstitutionAdmin> _admins = const [];
  List<AdminCandidate> _candidates = const [];
  String? _target;
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
    final admins = await widget.repository.list();
    final candidates = admins.failure == null ? await widget.repository.candidates() : null;
    if (!mounted) return;
    final current = {for (final a in admins.admins ?? const <InstitutionAdmin>[]) a.userId};
    setState(() {
      _loading = false;
      _admins = admins.admins ?? const [];
      _candidates = (candidates?.candidates ?? const <AdminCandidate>[])
          .where((c) => !current.contains(c.userId))
          .toList();
      if (_target != null && !_candidates.any((c) => c.userId == _target)) _target = null;
      _error = admins.failure?.message ?? candidates?.failure?.message;
    });
  }

  Future<void> _run(Future<LoadFailure?> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    final failure = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _code = '';
      if (failure == null) {
        _done = success;
        _target = null;
      } else {
        _error = failure.message ?? 'The request was refused.';
      }
    });
    if (failure == null) await _load();
  }

  Future<void> _remove(InstitutionAdmin admin) async {
    if (_code.trim().isEmpty) {
      setState(() => _error = 'Enter a fresh authenticator code first.');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Remove ${admin.username}?',
      message: 'They lose Institution Admin access at once and are signed out on every device.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    await _run(() => widget.repository.remove(userId: admin.userId, code: _code),
        '${admin.username} is no longer an Institution Admin and has been signed out.');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canAppoint = !_busy && _target != null && _code.trim().length >= 6;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space6),
        children: [
          const PageHeader(title: 'Institution Admins', padding: EdgeInsets.zero),
          const SizedBox(height: AppSpacing.space3),
          Text(
            'Only the institution owner can appoint or remove Institution Admins. '
            'Every change needs a fresh authenticator code for that person.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space6),
          if (_done != null) ...[
            InlineAlert(tone: InlineAlertTone.success, message: _done!),
            const SizedBox(height: AppSpacing.space4),
          ],
          if (_error != null) ...[
            InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            const SizedBox(height: AppSpacing.space4),
          ],
          AppTextField(
            key: const Key('institution-admin-code'),
            label: 'Authenticator code',
            required: true,
            value: _code,
            onChanged: (v) => setState(() => _code = v),
          ),
          const SizedBox(height: AppSpacing.space6),
          Text('Current Institution Admins',
              style: AppTypography.sectionHeading.copyWith(color: t.textPrimary)),
          const SizedBox(height: AppSpacing.space3),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_admins.isEmpty)
            Text('No Institution Admins yet.',
                style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary))
          else
            for (final a in _admins)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(a.username, style: AppTypography.personName.copyWith(color: t.textPrimary)),
                    ),
                    AppButton(
                      key: Key('remove-${a.userId}'),
                      label: 'Remove',
                      variant: AppButtonVariant.secondary,
                      onPressed: _busy ? null : () => _remove(a),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.space6),
          Text('Appoint an Institution Admin',
              style: AppTypography.sectionHeading.copyWith(color: t.textPrimary)),
          const SizedBox(height: AppSpacing.space3),
          if (!_loading && _candidates.isEmpty)
            Text('No eligible staff account with a login was found.',
                style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary))
          else
            DropdownButton<String>(
              key: const Key('institution-admin-target'),
              value: _target,
              isExpanded: true,
              hint: const Text('Choose a staff member'),
              items: [
                for (final c in _candidates)
                  DropdownMenuItem(value: c.userId, child: Text(c.name.isEmpty ? c.userId : c.name)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _target = v),
            ),
          const SizedBox(height: AppSpacing.space4),
          AppButton(
            key: const Key('institution-admin-appoint'),
            label: _busy ? 'Working…' : 'Appoint',
            fullWidth: true,
            onPressed: canAppoint
                ? () => _run(() => widget.repository.appoint(userId: _target!, code: _code),
                    'Appointed. They now have Institution Admin access.')
                : null,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';

/// Screen 3: bulk invoice generation.
///
/// The highest-consequence action in the app — it creates money records for
/// a whole class in one press, and **there is no invoice delete on this
/// backend**, so nothing generated can be taken back.
///
/// The screen therefore states, BEFORE the button is pressed: which plan,
/// which class, which period, and that the run cannot be undone. It also
/// states the one piece of good news, because it changes how carefully the
/// admin has to tread: a repeat run for the same period does NOT duplicate
/// invoices, it skips them (verified live — the second run reported
/// `generated: 0, skipped: 1`).
///
/// It does NOT promise a student count. The API has no dry run and no
/// per-plan student count, and inventing one from the enrolment list would
/// be a guess presented as a fact about money. The result, which is exact,
/// is shown afterwards instead.
class GenerateInvoicesScreen extends StatefulWidget {
  const GenerateInvoicesScreen({
    required this.repository,
    required this.plans,
    required this.classes,
    super.key,
  });

  final FinanceRepository repository;
  final List<FeePlan> plans;
  final List<SchoolClass> classes;

  @override
  State<GenerateInvoicesScreen> createState() => GenerateInvoicesScreenState();
}

class GenerateInvoicesScreenState extends State<GenerateInvoicesScreen> {
  String? _planId;
  String _period = '';
  bool _busy = false;
  String? _error;
  GenerationResult? _result;

  @override
  void initState() {
    super.initState();
    _planId = widget.plans.isEmpty ? null : widget.plans.first.id;
    final now = DateTime.now();
    _period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  FeePlan? get _plan {
    for (final p in widget.plans) {
      if (p.id == _planId) return p;
    }
    return null;
  }

  String _className(String id) {
    for (final c in widget.classes) {
      if (c.id == id) return c.name;
    }
    return 'its class';
  }

  /// `YYYY-MM`, the only form the backend accepts.
  bool get _periodLooksValid {
    final text = _period.trim();
    if (text.length != 7 || text[4] != '-') return false;
    final year = int.tryParse(text.substring(0, 4));
    final month = int.tryParse(text.substring(5));
    return year != null && month != null && month >= 1 && month <= 12;
  }

  Future<void> _confirmAndRun() async {
    final plan = _plan;
    if (plan == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generate these invoices?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Every student in ${_className(plan.classId)} will be invoiced '
              'for ${_period.trim()} under “${plan.name}”.',
            ),
            const SizedBox(height: AppSpacing.space4),
            const Text(
              'This cannot be undone — there is no way to delete an invoice '
              'on this system. Running it again for the same period is safe: '
              'invoices that already exist are skipped, not duplicated.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.repository.generate(
        planId: plan.id,
        period: _period.trim(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message ?? 'The invoices could not be generated.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final plan = _plan;
    final result = _result;

    return SetupScaffold(
      title: 'Generate invoices',
      note: const InlineAlert(
        tone: InlineAlertTone.warning,
        message: 'This creates real fee records for every student in the '
            'class. Invoices cannot be deleted on this system.',
      ),
      children: [
        Text(
          'Fee plan',
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            for (final p in widget.plans)
              PickerChip(
                label: p.name,
                selected: _planId == p.id,
                onTap: () => setState(() {
                  _planId = p.id;
                  _result = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        SetupField(
          label: 'Period (YYYY-MM)',
          value: _period,
          placeholder: 'e.g. 2026-09',
          onChanged: (v) => setState(() {
            _period = v;
            _result = null;
          }),
        ),
        if (!_periodLooksValid && _period.trim().isNotEmpty)
          Text(
            'A period is a year and a month, like 2026-09.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.danger),
          ),
        const SizedBox(height: AppSpacing.space6),

        // What will happen, in words, before it happens.
        if (plan != null && _periodLooksValid)
          Container(
            padding: const EdgeInsets.all(AppSpacing.space5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: t.border, width: AppSizing.borderThin),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What this will do',
                  style:
                      AppTypography.cardHeading.copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space3),
                Text(
                  'Invoice every student in ${_className(plan.classId)} for '
                  '${_period.trim()}, using “${plan.name}”.',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'How many students that is, and the amount each one is '
                  'charged, is decided by the server — this screen does not '
                  'estimate it. The exact result is shown once the run '
                  'finishes.',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.space6),

        AppButton(
          label: _busy ? 'Generating…' : 'Generate for this period',
          fullWidth: true,
          onPressed:
              _busy || plan == null || !_periodLooksValid ? null : _confirmAndRun,
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.space5),
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
        ],

        // D-29 submit confirmation — the one overshoot. Generation is the
        // highest-consequence action in the app, so its result lands.
        if (result != null) ...[
          const SizedBox(height: AppSpacing.space5),
          MotionConfirm(
            show: true,
            child: InlineAlert(
            tone: result.generated > 0
                ? InlineAlertTone.success
                : InlineAlertTone.info,
            message: result.generated > 0
                ? '${result.generated} '
                    '${result.generated == 1 ? 'invoice' : 'invoices'} '
                    'created for ${_period.trim()}'
                    '${result.skipped > 0 ? ', and ${result.skipped} '
                        'already existed and ${result.skipped == 1 ? 'was' : 'were'} '
                        'left alone' : ''}.'
                : 'Nothing was created. All ${result.total} '
                    '${result.total == 1 ? 'invoice' : 'invoices'} for '
                    '${_period.trim()} already existed.',
            ),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/money.dart';

/// Screen 2: fee plans — what one class is charged, per period.
///
/// The year is chosen HERE and sent explicitly. The backend's `current`
/// flag points at an expired year on live data, so a plan that let the
/// server resolve the year would bill against the wrong one and look
/// entirely plausible doing it. The screen names the year it will write.
class FeePlansScreen extends StatefulWidget {
  const FeePlansScreen({
    required this.repository,
    required this.classes,
    required this.heads,
    required this.year,
    required this.campusId,
    super.key,
  });

  final FinanceRepository repository;
  final List<SchoolClass> classes;
  final List<FeeHead> heads;
  final AcademicYear year;
  final String campusId;

  @override
  State<FeePlansScreen> createState() => FeePlansScreenState();
}

class FeePlansScreenState extends State<FeePlansScreen> {
  ScreenState<List<FeePlan>> _state =
      const ScreenState<List<FeePlan>>.loading();

  String _name = '';
  String? _classId;
  String _dueDay = '10';
  String _graceDays = '0';

  /// Head id → the amount typed for it. A head with no entry is not in the
  /// plan; a head with an unparseable entry blocks the save.
  final Map<String, String> _amounts = {};

  @override
  void initState() {
    super.initState();
    _classId = widget.classes.isEmpty ? null : widget.classes.first.id;
    _load();
  }

  Future<void> _load() async {
    setState(() =>
        _state = ScreenState<List<FeePlan>>.loading(previous: _state.data));
    try {
      final plans = await widget.repository.loadPlans();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<FeePlan>>.data(plans));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<FeePlan>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  /// The items typed so far, or null if any entry is not a valid amount.
  List<({String feeHeadId, Money amount})>? get _items {
    final items = <({String feeHeadId, Money amount})>[];
    for (final entry in _amounts.entries) {
      final text = entry.value.trim();
      if (text.isEmpty) continue;
      final amount = Money.tryParse(text);
      if (amount == null || !amount.isPositive) return null;
      items.add((feeHeadId: entry.key, amount: amount));
    }
    return items;
  }

  bool get _canSubmit {
    final items = _items;
    return _name.trim().isNotEmpty &&
        _classId != null &&
        items != null &&
        items.isNotEmpty &&
        int.tryParse(_dueDay.trim()) != null &&
        int.tryParse(_graceDays.trim()) != null;
  }

  Future<String?> _create() async {
    final items = _items;
    if (items == null || items.isEmpty) {
      return 'Enter an amount for at least one fee head. Amounts use up to '
          'two decimals.';
    }
    try {
      await widget.repository.createPlan(
        name: _name.trim(),
        frequency: 'monthly',
        classId: _classId!,
        academicYearId: widget.year.id,
        campusId: widget.campusId,
        dueDay: int.parse(_dueDay.trim()),
        graceDays: int.parse(_graceDays.trim()),
        items: items,
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _amounts.clear();
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      // 🔴 This endpoint answers 409 for a MISSING FIELD, not just a
      // duplicate — so the backend's own message is shown rather than a
      // guess at "that already exists".
      return f.message ?? 'The fee plan could not be created.';
    }
  }

  String _className(String id) {
    for (final c in widget.classes) {
      if (c.id == id) return c.name;
    }
    return 'Another class';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Fee plans',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message: 'New plans are created in “${widget.year.name}”. Invoices '
            'are generated from a plan, so the year is fixed when the plan '
            'is created.',
      ),
      children: [
        CreatePanel(
          addLabel: 'Add a fee plan',
          canSubmit: _canSubmit,
          onSubmit: _create,
          confirmNote: 'A plan cannot be edited or removed afterwards, and '
              'invoices already generated from it are not affected by '
              'anything you do later.',
          fields: [
            SetupField(
              label: 'Name',
              value: _name,
              placeholder: 'e.g. Grade 5 Monthly',
              onChanged: (v) => setState(() => _name = v),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Class',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final c in widget.classes)
                        PickerChip(
                          label: c.name,
                          selected: _classId == c.id,
                          onTap: () => setState(() => _classId = c.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SetupField(
              label: 'Due on day of month',
              value: _dueDay,
              onChanged: (v) => setState(() => _dueDay = v),
            ),
            SetupField(
              label: 'Grace days',
              value: _graceDays,
              onChanged: (v) => setState(() => _graceDays = v),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Amounts',
              style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Leave a head blank to keep it out of this plan. Up to two '
              'decimals — the server rounds anything finer.',
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space4),
            for (final h in widget.heads)
              SetupField(
                label: h.name,
                value: _amounts[h.id] ?? '',
                placeholder: '0.00',
                onChanged: (v) => setState(() => _amounts[h.id] = v),
              ),
            // No running total. The backend computes a plan's subtotal and
            // total, and adding them up here would create a second figure
            // that can disagree with the one the invoice is built from.
            Text(
              'The plan’s total is calculated by the server and shown once '
              'the plan is saved.',
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
            ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<FeePlan>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No fee plans yet',
            emptyMessage: 'A plan assembles fee heads into what one class '
                'pays each period. Invoices are generated from it.',
            emptyIcon: Icons.description_outlined,
            data: (context, plans) => ListView(
              children: [
                for (final p in plans)
                  SetupRow(
                    title: p.name,
                    detail: _className(p.classId),
                    trailing: p.dueDay == null ? null : 'Due day ${p.dueDay}',
                    onTap: () => _showPlan(p.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A plan's items and its SERVER-CALCULATED total, which only the detail
  /// endpoint carries.
  void _showPlan(String id) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _PlanSheet(
        future: widget.repository.loadPlan(id),
      ),
    );
  }
}

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({required this.future});

  final Future<FeePlan> future;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: FutureBuilder<FeePlan>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'This plan’s details could not be loaded.',
                style:
                    AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
              );
            }
            final plan = snapshot.data;
            if (plan == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.name,
                  style: AppTypography.cardHeading
                      .copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space4),
                for (final item in plan.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.feeHeadName,
                            style: AppTypography.bodyAdminMeta
                                .copyWith(color: t.textSecondary),
                          ),
                        ),
                        Text(
                          item.amount.format(),
                          style: AppTypography.personName
                              .copyWith(color: t.textPrimary),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.space4),
                if (plan.total != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total per period',
                        style: AppTypography.personName
                            .copyWith(color: t.textPrimary),
                      ),
                      Text(
                        plan.total!.format(),
                        style: AppTypography.personName
                            .copyWith(color: t.textPrimary),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../admin/data/admin_repository.dart';
import '../../setup/data/setup_repository.dart';
import '../../setup/domain/setup_models.dart';
// The same chrome the Setup hub uses. Finance is the second half of the
// same job — ordered steps where each needs the one above — so it composes
// those components rather than inventing a parallel set (T14 constraint:
// no new visual decisions).
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import 'collection_report_screen.dart';
import 'defaulters_screen.dart';
import 'fee_heads_screen.dart';
import 'fee_plans_screen.dart';
import 'generate_invoices_screen.dart';
import 'invoices_screen.dart';
import 'pending_payments_screen.dart';

/// Everything the finance screens need before they can write anything.
@immutable
class FinanceContext {
  const FinanceContext({
    required this.campusId,
    required this.years,
    required this.classes,
    required this.heads,
    required this.plans,
    required this.pendingCount,
  });

  final String? campusId;
  final List<AcademicYear> years;
  final List<SchoolClass> classes;
  final List<FeeHead> heads;
  final List<FeePlan> plans;
  final int pendingCount;

  /// The year a new fee plan is written against.
  ///
  /// 🔴 The backend's `current` flag is WRONG on live data — it points at an
  /// expired year (verified twice). Fees escape that bug only because a plan
  /// stores the year it was given, so the year is always chosen here and
  /// sent explicitly, and every screen that writes one states which it used.
  AcademicYear? get workingYear {
    for (final y in years) {
      if (y.current) return y;
    }
    return years.isEmpty ? null : years.first;
  }

  bool get usingFallbackYear => workingYear != null && !workingYear!.current;
}

/// The finance hub: fee setup, then the day-to-day money surfaces.
///
/// One tab, because the order is real — an invoice cannot exist without a
/// plan, and a plan cannot exist without a head. Each row states what it
/// needs rather than failing when opened.
class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({
    required this.finance,
    required this.setup,
    required this.admin,
    super.key,
  });

  final FinanceRepository finance;
  final SetupRepository setup;
  final AdminRepository admin;

  @override
  State<FinanceHomeScreen> createState() => FinanceHomeScreenState();
}

class FinanceHomeScreenState extends State<FinanceHomeScreen> {
  ScreenState<FinanceContext> _state =
      const ScreenState<FinanceContext>.loading();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() =>
        _state = ScreenState<FinanceContext>.loading(previous: _state.data));
    try {
      final campuses = await widget.admin.loadCampusIds();
      final years = await widget.setup.loadYears();
      final classes = await widget.setup.loadClasses();
      final heads = await widget.finance.loadHeads();
      final plans = await widget.finance.loadPlans();
      final pending = await widget.finance.loadPending();
      if (!mounted) return;
      setState(() => _state = ScreenState<FinanceContext>.data(
            FinanceContext(
              campusId: campuses.isEmpty ? null : campuses.first,
              years: years,
              classes: classes,
              heads: heads,
              plans: plans,
              pendingCount: pending.length,
            ),
            // A context object is one record, never a collection (D-39).
            isEmpty: false,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<FinanceContext>.failed(
            failure,
            cached: _state.data,
            connection: failure.unreachable
                ? NetworkStatus.offline
                : NetworkStatus.online,
          ));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ScreenStateBuilder<FinanceContext>(
          state: _state,
          onRetry: load,
          emptyTitle: 'Fees could not be opened',
          emptyMessage: 'The fee heads and plans could not be read. Reopen '
              'this tab to try again — if it keeps happening, tell your '
              'system administrator.',
          data: _body,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FinanceContext ctx) {
    final t = context.tokens;
    final year = ctx.workingYear;
    final noHeads = ctx.heads.isEmpty;
    final noPlans = ctx.plans.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Text(
          'Fees',
          style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Set the fees up once, then collect against them.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),

        if (ctx.campusId == null)
          const InlineAlert(
            tone: InlineAlertTone.danger,
            message: 'This school has no campus, so no fee plan can be '
                'created. Ask your system administrator.',
          )
        else if (year == null)
          const InlineAlert(
            tone: InlineAlertTone.info,
            message: 'Fee plans belong to an academic year. Create one under '
                'Setup first.',
          )
        else if (ctx.usingFallbackYear)
          InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'No year is marked as current, so fee plans will be '
                'created against “${year.name}”. The current year can only '
                'be changed by your system administrator.',
          ),
        const SizedBox(height: AppSpacing.space6),

        StepRow(
          number: 1,
          title: 'Fee heads',
          detail: 'The named parts of a fee: tuition, transport, admission.',
          count: ctx.heads.length,
          onTap: () => _open(FeeHeadsScreen(repository: widget.finance)),
        ),
        StepRow(
          number: 2,
          title: 'Fee plans',
          detail: 'What one class is charged, per period.',
          count: ctx.plans.length,
          onTap: (noHeads || year == null || ctx.campusId == null ||
                  ctx.classes.isEmpty)
              ? null
              : () => _open(FeePlansScreen(
                    repository: widget.finance,
                    classes: ctx.classes,
                    heads: ctx.heads,
                    year: year,
                    campusId: ctx.campusId!,
                  )),
          blockedReason: noHeads
              ? 'Create a fee head first'
              : year == null
                  ? 'Create an academic year first'
                  : ctx.classes.isEmpty
                      ? 'Create a class first'
                      : null,
        ),
        StepRow(
          number: 3,
          title: 'Generate invoices',
          detail: 'Bill a whole class for one period.',
          onTap: noPlans
              ? null
              : () => _open(GenerateInvoicesScreen(
                    repository: widget.finance,
                    plans: ctx.plans,
                    classes: ctx.classes,
                  )),
          blockedReason: noPlans ? 'Create a fee plan first' : null,
        ),
        StepRow(
          number: 4,
          title: 'Invoices',
          detail: 'Find an invoice and record a payment against it.',
          onTap: () => _open(InvoicesScreen(
            repository: widget.finance,
            classes: ctx.classes,
          )),
        ),
        StepRow(
          number: 5,
          title: 'Payments awaiting approval',
          detail: 'Recorded money is not counted until it is approved.',
          count: ctx.pendingCount,
          onTap: () => _open(PendingPaymentsScreen(repository: widget.finance)),
        ),
        StepRow(
          number: 6,
          title: 'Defaulters',
          detail: 'Who to chase, largest outstanding first.',
          onTap: () => _open(DefaultersScreen(
            repository: widget.finance,
            classes: ctx.classes,
          )),
        ),
        StepRow(
          number: 7,
          title: 'Collection report',
          detail: 'Invoiced against collected, by class.',
          onTap: () =>
              _open(CollectionReportScreen(repository: widget.finance)),
        ),
      ],
    );
  }
}

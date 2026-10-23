import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/stat_card.dart';
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
    this.report,
  });

  final String? campusId;
  final List<AcademicYear> years;
  final List<SchoolClass> classes;
  final List<FeeHead> heads;
  final List<FeePlan> plans;
  final int pendingCount;

  /// Overhaul M6: the money summary at the top of the hub. Null when it could
  /// not be read — the hub stays usable and says so instead of failing.
  final CollectionReport? report;

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
    setState(
      () => _state = ScreenState<FinanceContext>.loading(previous: _state.data),
    );
    try {
      // Only campuses where this account may manage fees (BUG-QA-08: a
      // Teacher@A + Finance@B account must never write fees against A).
      final campuses = await widget.admin.loadCampusIdsWith('fee.manage');
      // BUG-QA-13: a finance grant revoked mid-session leaves NO fee campus.
      // Show the permission state and drop cached money figures, instead of a
      // stale hub under a raw error banner (Pixel: blank screen + internal id).
      if (campuses.isEmpty) {
        throw const LoadFailure(
          kind: LoadFailureKind.forbidden,
          message:
              'No campus is available to your account for fees. If you need fee access, ask your institution’s administrator.',
        );
      }
      // BUG-QA-12: years and classes from campuses this account cannot manage
      // fees on (e.g. Teacher@A + Finance@B seeing A's year) are never offered.
      // Rows without a campus are kept (older servers / institution-wide).
      bool inScope(String? c) => c == null || campuses.contains(c);
      final years = (await widget.setup.loadYears())
          .where((y) => inScope(y.campusId))
          .toList();
      final classes = (await widget.setup.loadClasses())
          .where((k) => inScope(k.campusId))
          .toList();
      final heads = await widget.finance.loadHeads();
      final plans = await widget.finance.loadPlans();
      final pending = await widget.finance.loadPending();
      CollectionReport? report;
      try {
        report = await widget.finance.loadCollectionReport();
      } on Object {
        report = null;
      }
      if (!mounted) return;
      setState(
        () => _state = ScreenState<FinanceContext>.data(
          FinanceContext(
            campusId: campuses.isEmpty ? null : campuses.first,
            years: years,
            classes: classes,
            heads: heads,
            plans: plans,
            pendingCount: pending.length,
            report: report,
          ),
          // A context object is one record, never a collection (D-39).
          isEmpty: false,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(
        () => _state = ScreenState<FinanceContext>.failed(
          failure,
          // A refusal must not keep showing figures the account may no longer see.
          cached: failure.isForbidden ? null : _state.data,
          connection: failure.unreachable
              ? NetworkStatus.offline
              : NetworkStatus.online,
        ),
      );
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
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
          emptyMessage:
              'The fee heads and plans could not be read. Reopen '
              'this tab to try again — if it keeps happening, tell your '
              'system administrator.',
          data: _body,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, FinanceContext ctx) {
    final year = ctx.workingYear;
    final noHeads = ctx.heads.isEmpty;
    final noPlans = ctx.plans.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        const PageHeader(
          title: 'Fees',
          subtitle: 'Set the fees up once, then collect against them.',
          padding: EdgeInsets.only(bottom: AppSpacing.space5),
        ),
        _Summary(
          ctx: ctx,
          onOpenPending: () =>
              _open(PendingPaymentsScreen(repository: widget.finance)),
        ),
        const SizedBox(height: AppSpacing.space5),

        if (ctx.campusId == null)
          const InlineAlert(
            tone: InlineAlertTone.danger,
            message:
                'This institution has no campus, so no fee plan can be '
                'created. Ask your system administrator.',
          )
        else if (year == null)
          const InlineAlert(
            tone: InlineAlertTone.info,
            message:
                'Fee plans belong to an academic year. Create one under '
                'Setup first.',
          )
        else if (ctx.usingFallbackYear)
          InlineAlert(
            tone: InlineAlertTone.warning,
            message:
                'No year is marked as current, so fee plans will be '
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
          onTap:
              (noHeads ||
                  year == null ||
                  ctx.campusId == null ||
                  ctx.classes.isEmpty)
              ? null
              : () => _open(
                  FeePlansScreen(
                    repository: widget.finance,
                    classes: ctx.classes,
                    heads: ctx.heads,
                    year: year,
                    campusId: ctx.campusId!,
                  ),
                ),
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
              : () => _open(
                  GenerateInvoicesScreen(
                    repository: widget.finance,
                    plans: ctx.plans,
                    classes: ctx.classes,
                  ),
                ),
          blockedReason: noPlans ? 'Create a fee plan first' : null,
        ),
        StepRow(
          number: 4,
          title: 'Invoices',
          detail: 'Find an invoice and record a payment against it.',
          onTap: () => _open(
            InvoicesScreen(repository: widget.finance, classes: ctx.classes),
          ),
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
          onTap: () => _open(
            DefaultersScreen(repository: widget.finance, classes: ctx.classes),
          ),
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

/// Collected / outstanding / awaiting approval, all from fee.manage endpoints
/// the hub already needs — no learner data, so finance staff see it in full.
class _Summary extends StatelessWidget {
  const _Summary({required this.ctx, required this.onOpenPending});

  final FinanceContext ctx;
  final VoidCallback onOpenPending;

  @override
  Widget build(BuildContext context) {
    final r = ctx.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: const Key('finance-summary'),
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            // M1 motion: a one-shot staggered arrival for the money summary
            // (reduced motion keeps only the fade; never on tab switches).
            if (r != null) ...[
              MotionReveal.staggered(
                index: 0,
                child: StatCard(
                  value: r.totalCollected.format(),
                  label: 'Collected',
                  tone: StatCardTone.success,
                ),
              ),
              MotionReveal.staggered(
                index: 1,
                child: StatCard(
                  value: r.outstanding.format(),
                  label: 'Outstanding',
                  tone: r.outstanding.paisa > 0
                      ? StatCardTone.warning
                      : StatCardTone.neutral,
                  sub: 'of ${r.totalInvoiced.format()} invoiced',
                ),
              ),
            ],
            StatCard(
              value: '${ctx.pendingCount}',
              label: ctx.pendingCount == 1
                  ? 'Payment awaiting approval'
                  : 'Payments awaiting approval',
              tone: ctx.pendingCount > 0
                  ? StatCardTone.info
                  : StatCardTone.neutral,
              onTap: ctx.pendingCount > 0 ? onOpenPending : null,
            ),
          ],
        ),
        if (r == null) ...[
          const SizedBox(height: AppSpacing.space3),
          const InlineAlert(
            tone: InlineAlertTone.info,
            message:
                'Collection totals could not be loaded. The fee tools below still work; reopen Fees to try again.',
          ),
        ],
      ],
    );
  }
}

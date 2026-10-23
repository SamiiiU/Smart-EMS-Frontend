import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';

/// The one sign-in frame (overhaul M1), shared by login, two-factor
/// enrolment/verification and change password, so the whole authentication
/// journey looks like one product:
/// - wide screens (>= [splitAt]): a brand panel beside the content card;
/// - phones: a compact brand row above the card.
/// The card scrolls, so long content (recovery codes, large text, an open
/// keyboard) never hides the primary action. Content is supplied by the
/// screen; this widget adds no controls of its own.
class AuthLayout extends StatelessWidget {
  const AuthLayout({required this.child, super.key});

  final Widget child;

  static const double splitAt = 900;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= splitAt;
        final card = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              wide ? AppSpacing.space10 : AppSpacing.space6,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizing.authFormMaxWidth + 2 * AppSpacing.space8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!wide) ...[
                    const AuthBrandStrip(),
                    const SizedBox(height: AppSpacing.space6),
                  ],
                  Container(
                    padding: EdgeInsets.all(
                      wide ? AppSpacing.space9 : AppSpacing.space7,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadius.xl2),
                      border: Border.all(color: t.border),
                    ),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        );
        if (!wide) return card;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(flex: 5, child: AuthBrandPanel()),
            Expanded(flex: 6, child: card),
          ],
        );
      },
    );
  }
}

/// Brand side of the wide layout. Static text only: nothing that looks tappable.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.onBrandMuted, size: 22),
          const SizedBox(width: AppSpacing.space5),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyTeacher.copyWith(color: t.onBrand),
            ),
          ),
        ],
      ),
    );
    return Container(
      color: t.brandSurface,
      padding: const EdgeInsets.all(AppSpacing.space10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.school_outlined, color: t.onBrand, size: 40),
              const SizedBox(height: AppSpacing.space6),
              Text(
                'One place for your institution’s daily work',
                style: AppTypography.parentStatusHero.copyWith(
                  color: t.onBrand,
                ),
              ),
              const SizedBox(height: AppSpacing.space8),
              line(
                Icons.fact_check_outlined,
                'Attendance that keeps working when the connection drops.',
              ),
              line(
                Icons.payments_outlined,
                'Fees, payments and receipts with approval built in.',
              ),
              line(
                Icons.family_restroom_outlined,
                'Results and progress for families and learners.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact brand header above the card on phones.
class AuthBrandStrip extends StatelessWidget {
  const AuthBrandStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: t.brandSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Icon(Icons.school_outlined, color: t.onBrand, size: 22),
        ),
        const SizedBox(width: AppSpacing.space5),
        Expanded(
          child: Text(
            'Educational management for your institution',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}

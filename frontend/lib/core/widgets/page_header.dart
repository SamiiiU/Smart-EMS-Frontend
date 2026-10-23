import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';

/// The one page header (overhaul M1).
///
/// Before this, each screen composed its own title Text, subtitle and action
/// Row with slightly different spacing, and on a 320 px phone a long title
/// pushed its action button off-screen or into an overflow. Rules:
/// - the title is a semantic header and may wrap; it is never truncated;
/// - [subtitle] says what the page is for, in one line of plain words;
/// - [actions] sit to the right when there is room and WRAP below the title
///   on narrow screens, so a primary action is never hidden;
/// - spacing comes from the scale, so every page starts at the same rhythm.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.space6,
      AppSpacing.space6,
      AppSpacing.space6,
      AppSpacing.space5,
    ),
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  /// Below this width the actions move under the title.
  static const double stackBelow = 560;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            subtitle!,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ],
      ],
    );
    if (actions.isEmpty) return Padding(padding: padding, child: heading);

    final actionBar = Wrap(
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space3,
      alignment: WrapAlignment.end,
      children: actions,
    );
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < stackBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: AppSpacing.space5),
                actionBar,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.space6),
              actionBar,
            ],
          );
        },
      ),
    );
  }
}

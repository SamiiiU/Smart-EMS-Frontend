import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum RowTint { none, danger, warning }

/// The workhorse row: leading avatar or time column, title, subtitle, trailing
/// pill or chevron, optional row tint.
///
/// THE WHOLE ROW IS THE TAP TARGET, not just the trailing control. This was
/// established on the attendance screen to reduce mis-taps — a teacher marking
/// a 40-student roll should not have to hit a small pill. Implemented with an
/// opaque hit test across the full row, so a tap near the leading edge fires
/// [onTap]. There is a test asserting exactly that.
class ListRow extends StatelessWidget {
  const ListRow({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.tint = RowTint.none,
    this.minHeight = AppSizing.listRowMinHeight,
    this.onTap,
    super.key,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final RowTint tint;
  final double minHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final bg = switch (tint) {
      RowTint.none => SmartEmsTokens.transparent,
      RowTint.danger => t.rowTintDanger,
      RowTint.warning => t.rowTintWarning,
    };

    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space4,
      ),
      color: bg,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.space5),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.personName.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    subtitle!,
                    style: AppTypography.bodyAdminMeta.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.space5),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        // HitTestBehavior.opaque is what makes the WHOLE row tappable,
        // including padding and the gaps between children. Without it, taps
        // landing on empty space would fall through.
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}

/// A [ListRow] variant with a fixed-width time column, shared by Teacher today
/// and Student timetable so the two read as the same object.
///
/// Breaks are rendered as a MUTED ROW rather than being omitted: a gap in a
/// timetable reads as missing data, which is worse than a row that says
/// "Break".
class PeriodRow extends StatelessWidget {
  const PeriodRow({
    required this.time,
    required this.title,
    this.subtitle,
    this.trailing,
    this.isBreak = false,
    this.tint = RowTint.none,
    this.onTap,
    super.key,
  });

  /// Short time label, e.g. "09:40". Tabular figures keep the column aligned.
  final String time;

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Renders the row muted instead of hiding it.
  final bool isBreak;

  final RowTint tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final timeColumn = SizedBox(
      width: AppSizing.periodTimeColumnWidth,
      child: Text(
        time,
        style: AppTypography.timestamp.copyWith(
          color: isBreak ? t.textMuted : t.textSecondary,
        ),
      ),
    );

    if (!isBreak) {
      return ListRow(
        leading: timeColumn,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        tint: tint,
        onTap: onTap,
      );
    }

    // Muted break row: present, clearly not a lesson, and not tappable.
    return Container(
      constraints: const BoxConstraints(
        minHeight: AppSizing.listRowMinHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space4,
      ),
      color: t.surfaceSunken,
      child: Row(
        children: [
          timeColumn,
          const SizedBox(width: AppSpacing.space5),
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodyAdminMeta.copyWith(color: t.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

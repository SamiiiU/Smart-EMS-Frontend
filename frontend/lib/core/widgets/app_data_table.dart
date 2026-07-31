import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import 'list_row.dart';
import 'status_pill.dart';

/// One row of table data.
class AppDataRow {
  const AppDataRow({
    required this.cells,
    this.status,
    this.tint = RowTint.none,
    this.onTap,
  });

  /// One entry per column, same order and length as the table's columns.
  final List<String> cells;

  /// Optional per-row status, rendered as a [StatusPill].
  final AppStatus? status;

  final RowTint tint;
  final VoidCallback? onTap;
}

/// Header band plus rows, with per-row status and optional row tint.
///
/// Two uses (admin dashboard, students list) which are structurally identical.
///
/// **Collapses to stacked cards below [AppSizing.tableCollapseBreakpoint]
/// (600px) and NEVER scrolls horizontally.** Horizontal scrolling in a data
/// table hides columns off-screen with no affordance, and on a phone it fights
/// the vertical scroll of the page. Below the breakpoint each row becomes a
/// card of `label: value` pairs, so every column stays reachable.
///
/// Named `AppDataTable` rather than `DataTable` because Flutter's Material
/// library already exports a `DataTable`.
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    required this.columns,
    required this.rows,
    this.statusColumnLabel = 'Status',
    super.key,
  });

  /// Column headers, in order.
  final List<String> columns;

  final List<AppDataRow> rows;

  /// Header shown above the status column in wide mode, and used as the label
  /// for the status line in collapsed mode.
  final String statusColumnLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapse =
            constraints.maxWidth < AppSizing.tableCollapseBreakpoint;
        return collapse ? _Stacked(table: this) : _Wide(table: this);
      },
    );
  }
}

class _Wide extends StatelessWidget {
  const _Wide({required this.table});

  final AppDataTable table;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasStatus = table.rows.any((r) => r.status != null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header band
        Container(
          color: t.surfaceSunken,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space5,
            vertical: AppSpacing.space4,
          ),
          child: Row(
            children: [
              for (final c in table.columns)
                Expanded(
                  child: Text(
                    c.toUpperCase(),
                    style: AppTypography.overlineTracked.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ),
              if (hasStatus)
                Expanded(
                  child: Text(
                    table.statusColumnLabel.toUpperCase(),
                    style: AppTypography.overlineTracked.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final row in table.rows) ...[
          Divider(
            height: AppSizing.borderThin,
            thickness: AppSizing.borderThin,
            color: t.border,
          ),
          _WideRow(row: row, hasStatus: hasStatus),
        ],
      ],
    );
  }
}

class _WideRow extends StatelessWidget {
  const _WideRow({required this.row, required this.hasStatus});

  final AppDataRow row;
  final bool hasStatus;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final bg = switch (row.tint) {
      RowTint.none => t.surface,
      RowTint.danger => t.rowTintDanger,
      RowTint.warning => t.rowTintWarning,
    };

    final content = Container(
      constraints: const BoxConstraints(
        minHeight: AppSizing.listRowMinHeight,
      ),
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space4,
      ),
      child: Row(
        children: [
          for (final cell in row.cells)
            Expanded(
              child: Text(
                cell,
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textPrimary,
                ),
              ),
            ),
          if (hasStatus)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: row.status == null
                    ? const SizedBox.shrink()
                    : StatusPill(status: row.status!, size: StatusPillSize.sm),
              ),
            ),
        ],
      ),
    );

    if (row.onTap == null) return content;
    return GestureDetector(
      onTap: row.onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

/// Below 600px: one card per row, every column as a `label: value` pair.
/// Nothing is hidden and nothing scrolls sideways.
class _Stacked extends StatelessWidget {
  const _Stacked({required this.table});

  final AppDataTable table;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in table.rows) ...[
          _StackedCard(table: table, row: row, tokensBorder: t.border),
          const SizedBox(height: AppSpacing.space4),
        ],
      ],
    );
  }
}

class _StackedCard extends StatelessWidget {
  const _StackedCard({
    required this.table,
    required this.row,
    required this.tokensBorder,
  });

  final AppDataTable table;
  final AppDataRow row;
  final Color tokensBorder;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final bg = switch (row.tint) {
      RowTint.none => t.surface,
      RowTint.danger => t.rowTintDanger,
      RowTint.warning => t.rowTintWarning,
    };

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokensBorder, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < table.columns.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.space3),
            Text(
              table.columns[i].toUpperCase(),
              style: AppTypography.overlineTracked.copyWith(
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              i < row.cells.length ? row.cells[i] : '',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textPrimary,
              ),
            ),
          ],
          if (row.status != null) ...[
            const SizedBox(height: AppSpacing.space4),
            StatusPill(status: row.status!, size: StatusPillSize.sm),
          ],
        ],
      ),
    );

    if (row.onTap == null) return card;
    return GestureDetector(
      onTap: row.onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

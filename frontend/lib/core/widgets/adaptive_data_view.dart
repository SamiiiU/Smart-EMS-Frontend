import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import 'app_button.dart';

/// One column of an [AdaptiveDataView].
class DataColumnSpec<T> {
  const DataColumnSpec({
    required this.label,
    required this.value,
    this.flex = 1,
    this.numeric = false,
    this.cell,
    this.interactive = false,
  });

  /// Header text (table) and field label (card).
  final String label;
  final String Function(T row) value;
  final int flex;

  /// Right-aligned with tabular figures (money, counts).
  final bool numeric;

  /// Optional rich cell (a status pill, a warning colour). [value] is still
  /// required: it is the plain text used by screen readers and sorting.
  final Widget Function(T row)? cell;

  /// True when [cell] is an input (a text field, a checkbox). A row otherwise
  /// folds all of its content into one node named by the row label, which hid
  /// such inputs from screen readers entirely (Android TalkBack, report 11).
  /// An interactive cell keeps its own semantics; the row's static text is
  /// still folded into the row label so nothing is read twice.
  final bool interactive;
}

/// One contextual action on a row of an [AdaptiveDataView] (M5), e.g.
/// Approve / Reject on a pending payment.
///
/// UI state only: hiding or disabling an action is a convenience. The server
/// remains the authority on every operation; a hidden action is NOT a security
/// control.
class RowAction<T> {
  const RowAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.secondary,
    this.semanticLabel,
    this.isVisible,
    this.isEnabled,
    this.isLoading,
    this.disabledReason,
    this.loadingLabel,
    this.key,
  });

  final String label;

  /// May be async: the button disables itself until the future completes, so
  /// a double tap cannot run the action twice.
  final FutureOr<void> Function(T row) onPressed;
  final IconData? icon;
  final AppButtonVariant variant;

  /// Full accessible name, e.g. "Approve payment for Ayesha Khan". Defaults to
  /// "label, row semantic label" so an action is never ambiguous in a list.
  final String Function(T row)? semanticLabel;

  /// Permission or state restriction: false hides the action for this row.
  final bool Function(T row)? isVisible;

  /// False shows the action disabled, with [disabledReason] as tooltip + hint.
  final bool Function(T row)? isEnabled;

  /// True while the screen is processing this action for this row.
  final bool Function(T row)? isLoading;
  final String? Function(T row)? disabledReason;
  final String? loadingLabel;

  /// Optional key per row, e.g. for tests.
  final Key Function(T row)? key;
}

/// The one data-list pattern (overhaul M1).
///
/// - **Desktop / tablet (>= [tableBreakpoint])**: a readable table: header row,
///   aligned columns, row dividers, hover tint, numbers right-aligned.
/// - **Phone**: structured cards: the first column as the card title, the rest
///   as label: value lines, so nothing is cut off or scrolled sideways.
///
/// Both layouts use the SAME columns, the same [onTap] and the same semantics
/// (each row is one button named by [semanticLabel]), so switching width never
/// changes what a user can do or what a screen reader announces.
class AdaptiveDataView<T> extends StatelessWidget {
  const AdaptiveDataView({
    required this.rows,
    required this.columns,
    required this.semanticLabel,
    this.onTap,
    this.rowKey,
    this.rowActions = const [],
    this.actionsLabel = 'Actions',
    this.actionsFlex = 3,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
    super.key,
  }) : assert(columns.length > 0);

  final List<T> rows;
  final List<DataColumnSpec<T>> columns;
  final String Function(T row) semanticLabel;
  final void Function(T row)? onTap;
  final Key Function(T row)? rowKey;

  /// Optional per-row actions (M5). Rendered OUTSIDE the row's tap target in
  /// both layouts, so pressing an action never also opens the row.
  final List<RowAction<T>> rowActions;

  /// Table header for the actions column.
  final String actionsLabel;
  final int actionsFlex;
  final EdgeInsetsGeometry padding;

  static const double tableBreakpoint = 720;

  List<RowAction<T>> _visibleActions(T row) => [
    for (final a in rowActions)
      if (a.isVisible?.call(row) ?? true) a,
  ];

  Widget _actionBar(T row, {required WrapAlignment alignment}) {
    final actions = _visibleActions(row);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: alignment,
      spacing: AppSpacing.space3,
      runSpacing: AppSpacing.space3,
      children: [
        for (final a in actions)
          _RowActionButton<T>(
            key: a.key?.call(row),
            action: a,
            row: row,
            rowLabel: semanticLabel(row),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= tableBreakpoint
          ? _table(context)
          : _cards(context),
    );
  }

  /// True when some column holds an input. Such rows cannot fold ALL their
  /// content into the row node (that hid the inputs from screen readers);
  /// only the static parts are excluded instead, via [_quiet].
  bool get _hasInteractive =>
      columns.any((c) => c.interactive && c.cell != null);

  /// Static row content that the row label already announces.
  Widget _quiet(Widget w) => _hasInteractive ? ExcludeSemantics(child: w) : w;

  /// A cell built by [DataColumnSpec.cell]: inputs stay accessible.
  /// An input is named "column label, row title" (e.g. "Marks, Ayesha Khan"):
  /// without it TalkBack announced only "edit box" / "checkbox".
  Widget _customCell(DataColumnSpec<T> c, T row) => c.interactive
      ? Semantics(
          label: '${c.label}, ${columns.first.value(row)}',
          child: c.cell!(row),
        )
      : _quiet(c.cell!(row));

  Widget _tappable(BuildContext context, T row, Widget child) {
    final tap = onTap;
    final content = _hasInteractive ? child : ExcludeSemantics(child: child);
    if (tap == null) {
      return Semantics(
        label: semanticLabel(row),
        container: true,
        child: content,
      );
    }
    return Semantics(
      key: rowKey?.call(row),
      button: true,
      label: semanticLabel(row),
      child: InkWell(
        onTap: () => tap(row),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: content,
      ),
    );
  }

  Widget _table(BuildContext context) {
    final t = context.tokens;
    TextStyle head = AppTypography.fieldLabel.copyWith(color: t.textSecondary);
    // Every header and data cell gets the same gutter, so a right-aligned
    // number never touches the next column (seen on Invoices: "OutstandingStatus").
    const gutter = EdgeInsets.symmetric(horizontal: AppSpacing.space4);
    Widget cell(
      String text,
      DataColumnSpec<T> c, {
      bool first = false,
      bool quiet = false,
      TextStyle? style,
    }) => Expanded(
      flex: c.flex,
      child: Padding(
        padding: gutter,
        child: (quiet ? _quiet : (Widget w) => w)(
          Text(
            text,
            textAlign: c.numeric ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                style ??
                (first
                    ? AppTypography.personName.copyWith(color: t.textPrimary)
                    : AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      )),
          ),
        ),
      ),
    );
    return ListView.builder(
      padding: padding,
      itemCount: rows.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space4,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.borderStrong)),
            ),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  for (final c in columns) cell(c.label, c, style: head),
                  if (onTap != null) const SizedBox(width: 24),
                  if (rowActions.isNotEmpty)
                    Expanded(
                      flex: actionsFlex,
                      child: Padding(
                        padding: gutter,
                        child: Text(
                          actionsLabel,
                          textAlign: TextAlign.right,
                          style: head,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        final row = rows[i - 1];
        final mainCells = _tappable(
          context,
          row,
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizing.listRowMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space5,
                vertical: AppSpacing.space4,
              ),
              child: Row(
                children: [
                  for (final (j, c) in columns.indexed)
                    if (c.cell != null)
                      Expanded(
                        flex: c.flex,
                        child: Padding(
                          padding: gutter,
                          child: Align(
                            alignment: c.numeric
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: _customCell(c, row),
                          ),
                        ),
                      )
                    else
                      cell(c.value(row), c, first: j == 0, quiet: true),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 24, color: t.textSecondary),
                ],
              ),
            ),
          ),
        );
        final totalFlex = columns.fold<int>(0, (sum, c) => sum + c.flex);
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: rowActions.isEmpty
              ? mainCells
              : Row(
                  children: [
                    Expanded(flex: totalFlex, child: mainCells),
                    Expanded(
                      flex: actionsFlex,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space4,
                          vertical: AppSpacing.space3,
                        ),
                        child: _actionBar(row, alignment: WrapAlignment.end),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _cards(BuildContext context) {
    final t = context.tokens;
    return ListView.builder(
      padding: padding,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final title = columns.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.space3),
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: t.border, width: AppSizing.borderThin),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tappable(
                  context,
                  row,
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.space5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _quiet(
                                Text(
                                  title.value(row),
                                  style: AppTypography.personName.copyWith(
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                              for (final c in columns.skip(1)) ...[
                                const SizedBox(height: AppSpacing.space2),
                                if (c.cell != null)
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: AppSpacing.space3,
                                    children: [
                                      _quiet(
                                        Text(
                                          '${c.label}:',
                                          style: AppTypography.caption.copyWith(
                                            color: t.textMuted,
                                          ),
                                        ),
                                      ),
                                      _customCell(c, row),
                                    ],
                                  )
                                else
                                  _quiet(
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${c.label}: ',
                                            style: AppTypography.caption
                                                .copyWith(color: t.textMuted),
                                          ),
                                          TextSpan(
                                            text: c.value(row),
                                            style: AppTypography.bodyAdminMeta
                                                .copyWith(
                                                  color: t.textSecondary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        if (onTap != null)
                          Icon(Icons.chevron_right, color: t.textSecondary),
                      ],
                    ),
                  ),
                ),
                if (_visibleActions(row).isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.space5,
                      AppSpacing.space3,
                      AppSpacing.space5,
                      AppSpacing.space4,
                    ),
                    child: _actionBar(row, alignment: WrapAlignment.start),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One row action. Owns an in-flight guard so a double tap cannot run the
/// action twice, whether or not the screen reports [RowAction.isLoading].
class _RowActionButton<T> extends StatefulWidget {
  const _RowActionButton({
    required this.action,
    required this.row,
    required this.rowLabel,
    super.key,
  });

  final RowAction<T> action;
  final T row;
  final String rowLabel;

  @override
  State<_RowActionButton<T>> createState() => _RowActionButtonState<T>();
}

class _RowActionButtonState<T> extends State<_RowActionButton<T>> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      await widget.action.onPressed(widget.row);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final row = widget.row;
    // When the screen reports loading itself, trust it: an action that first
    // asks for confirmation is "running" while the dialog is open, but nothing
    // is being processed yet, so it must not read "Approving…".
    final loading = a.isLoading != null ? a.isLoading!(row) : _running;
    // The button stays ENABLED while its own action runs (e.g. its dialog or
    // sheet is open): a disabled button gives up keyboard focus, and focus
    // then cannot return to it when the dialog closes. The in-flight guard in
    // _run makes any further press a no-op, so it still cannot run twice.
    // Only the SCREEN's loading/enabled state disables it.
    final screenLoading = a.isLoading?.call(row) ?? false;
    final enabled = !screenLoading && (a.isEnabled?.call(row) ?? true);
    final reason = enabled || loading ? null : a.disabledReason?.call(row);
    final name = a.semanticLabel?.call(row) ?? '${a.label}, ${widget.rowLabel}';
    Widget button = AppButton(
      label: loading ? (a.loadingLabel ?? '${a.label}…') : a.label,
      icon: loading ? null : a.icon,
      variant: a.variant,
      size: AppButtonSize.sm,
      onPressed: enabled ? _run : null,
      // Name and hint go through AppButton so its single semantics node keeps
      // the focus flags web needs for Tab (no wrapping ExcludeSemantics).
      semanticsLabel: name,
      semanticsHint: reason,
    );
    if (reason != null) {
      // The reason is already the hint; do not announce it twice.
      button = Tooltip(
        message: reason,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return Semantics(liveRegion: loading, child: button);
  }
}

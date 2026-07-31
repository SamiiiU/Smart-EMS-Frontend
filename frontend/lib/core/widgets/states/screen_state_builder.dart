import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/scales.dart';
import '../../theme/typography.dart';
import '../inline_alert.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'loading_skeleton.dart';
import 'screen_state.dart';

/// Applies THE precedence rule so a screen cannot express it itself.
///
/// This is the actual deliverable of T4. Six widgets are the easy part; the
/// valuable output is one implementation of the ordering, because built
/// per-screen it drifts — and the previous build proved it. Some screens showed
/// a spinner, some a blank area, some nothing, and "no results" was
/// indistinguishable from "not loaded yet".
///
/// A screen supplies its DATA builder and its empty/error copy. It does not get
/// to decide when a state wins over data: [resolveOutcome] does, once.
///
/// Rows 2, 4 and 6 of the rule are D-30 — existing data is never replaced by a
/// state. When cached or prior data exists, that data renders, adorned with an
/// offline indicator or a non-blocking failure notice. A user who can already
/// see rows does not lose them because a refresh failed or the network dropped.
class ScreenStateBuilder<T> extends StatelessWidget {
  const ScreenStateBuilder({
    required this.state,
    required this.data,
    required this.onRetry,
    required this.emptyTitle,
    required this.emptyMessage,
    this.skeleton = const LoadingSkeleton.listRows(),
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.filterDescription,
    this.onClearFilter,
    super.key,
  })  : assert(
          (emptyActionLabel == null) == (onEmptyAction == null),
          'An empty-state action needs both a label and a callback (D-19).',
        ),
        assert(
          // If a screen can filter, it must be able to clear the filter —
          // otherwise FilteredEmptyState would be a dead end.
          (filterDescription == null) == (onClearFilter == null),
          'A filterable screen must supply both filterDescription and '
          'onClearFilter, so FilteredEmptyState can always offer a way out.',
        );

  final ScreenState<T> state;

  /// Renders the actual content. Called for rows 2, 4, 6 and 10.
  final Widget Function(BuildContext context, T value) data;

  final VoidCallback onRetry;

  final Widget skeleton;

  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  /// Required together, and only for screens that can filter.
  final String? filterDescription;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    final outcome = resolveOutcome(state);

    switch (outcome) {
      case ScreenOutcome.unlinkedProfileState:
        return const UnlinkedProfileState();

      case ScreenOutcome.offlineState:
        return const OfflineState();

      case ScreenOutcome.loadingSkeleton:
        return skeleton;

      case ScreenOutcome.errorState:
        return ErrorState(
          message: state.failure?.message,
          onRetry: onRetry,
        );

      case ScreenOutcome.filteredEmptyState:
        return FilteredEmptyState(
          filterDescription: filterDescription!,
          onClearFilter: onClearFilter!,
        );

      case ScreenOutcome.emptyState:
        return EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
        );

      case ScreenOutcome.data:
        final adornment = adornmentFor(state);
        final value = state.data;
        // resolveOutcome only returns `data` when hasData, so this cannot be
        // null. Handled explicitly rather than with `!` because T is itself
        // nullable-capable.
        if (value == null) return skeleton;
        final content = data(context, value);
        if (!adornment.any) return content;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (adornment.showRefreshFailedNotice) ...[
              // Non-blocking: the rows below are still usable. Inline and
              // persistent, never a snackbar — same contract as InlineAlert.
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space4),
                child: InlineAlert(
                  tone: InlineAlertTone.warning,
                  message: state.failure?.message ??
                      'Could not refresh. Showing the last data loaded.',
                ),
              ),
            ],
            if (adornment.showOfflineIndicator) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.space4),
                child: OfflineBanner(),
              ),
            ],
            content,
          ],
        );
    }
  }
}

/// The row-2 adornment: offline, but there IS cached data, so the data renders
/// and this sits above it.
///
/// Deliberately not an [InlineAlert] with a danger or warning tone — offline is
/// a mode, not a fault. Neutral surface, neutral text.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    this.message = 'Offline — showing saved data.',
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space5,
          vertical: AppSpacing.space4,
        ),
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: AppSpacing.space6,
              color: t.textSecondary,
            ),
            const SizedBox(width: AppSpacing.space4),
            Expanded(
              child: Text(
                message,
                // textPrimary, not primaryTextOnSurface — this sits on
                // surfaceSunken, where that token is banned (D-36).
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

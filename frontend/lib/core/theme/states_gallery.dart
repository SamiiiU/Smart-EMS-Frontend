import 'package:flutter/material.dart';

import '../widgets/states/empty_state.dart';
import '../widgets/states/error_state.dart';
import '../widgets/states/loading_skeleton.dart';
import '../widgets/states/screen_state.dart';
import '../widgets/states/screen_state_builder.dart';
import 'app_theme.dart';
import 'scales.dart';
import 'sizing.dart';
import 'typography.dart';

/// The global-states half of the living gallery (T4).
///
/// Shows all six components plus every row of the precedence rule, so the
/// ordering can be reviewed by looking at it rather than by reading the table.
class StatesGallerySection extends StatelessWidget {
  const StatesGallerySection({super.key});

  static const _rows = ['Ayesha Khan', 'Bilal Mehmood', 'Fatima Siddiqui'];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _H('Global states'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'Six components plus the precedence rule that decides which one a '
          'screen shows. The rule is implemented once, so no screen decides '
          'for itself.',
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- LoadingSkeleton ------------------------------------------
        const _H('LoadingSkeleton'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'Skeletons, never a spinner. Dimensions match the real content, so '
          'nothing shifts when data arrives — the list-row skeleton is exactly '
          'ListRow.minHeight. Shimmer is the one permitted looping animation '
          '(opacity only), and it stops under prefers-reduced-motion.',
        ),
        const SizedBox(height: AppSpacing.space5),
        for (final variant in SkeletonVariant.values) ...[
          Text(
            'variant: ${variant.name}',
            style: AppTypography.overline.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          _Frame(child: LoadingSkeleton(variant: variant, count: 3)),
          const SizedBox(height: AppSpacing.space6),
        ],
        const SizedBox(height: AppSpacing.space6),

        // --- EmptyState -----------------------------------------------
        const _H('EmptyState'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'The action is governed by D-19 — offered only when it exists. A '
          'label without a callback is unrepresentable.',
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'with an action (a student list CAN be imported into)',
          style: AppTypography.overline.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space3),
        _Frame(
          child: EmptyState(
            icon: Icons.groups_outlined,
            title: 'No students yet',
            message: 'Import a class list to get started.',
            actionLabel: 'Import students',
            onAction: () {},
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'without an action (nothing the user does about an empty inbox)',
          style: AppTypography.overline.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space3),
        const _Frame(
          child: EmptyState(
            icon: Icons.notifications_none_outlined,
            title: 'No notifications',
            message: 'Anything new from your school will appear here.',
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- FilteredEmptyState ---------------------------------------
        const _H('FilteredEmptyState'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'A separate component, not EmptyState with a flag (D-14). It states '
          'which filter matched nothing, and the clear action ALWAYS exists — '
          'a filter the user cannot clear is a trap.',
        ),
        const SizedBox(height: AppSpacing.space5),
        _Frame(
          child: FilteredEmptyState(
            filterDescription: 'Class 9-C with status "Absent"',
            onClearFilter: () {},
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- ErrorState -----------------------------------------------
        const _H('ErrorState'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'The backend message is shown VERBATIM — it names the real problem '
          'and often the next step. Press retry twice to see the escalation '
          '(D-11): a button that visibly does nothing is worse than one that '
          'explains.',
        ),
        const SizedBox(height: AppSpacing.space5),
        _Frame(
          child: ErrorState(
            message: 'Attendance for this date is locked and cannot be edited.',
            onRetry: () {},
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- OfflineState ---------------------------------------------
        const _H('OfflineState'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'Reached only when there is NO cached data. Not an error and must '
          'not look like one — no danger colour, no failure icon. Offline is a '
          'mode, not a fault. No retry: retrying does not create a network.',
        ),
        const SizedBox(height: AppSpacing.space5),
        const _Frame(child: OfflineState()),
        const SizedBox(height: AppSpacing.space8),

        // --- UnlinkedProfileState -------------------------------------
        const _H('UnlinkedProfileState'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'A 404 from /staff/me or /students/me. Not an error either — the '
          'login exists but was never linked to a person record (the D-17 '
          'orphan case). No retry: the user cannot fix this, so it points at '
          'the administrator instead.',
        ),
        const SizedBox(height: AppSpacing.space5),
        const _Frame(child: UnlinkedProfileState()),
        const SizedBox(height: AppSpacing.space10),

        // --- The precedence rule --------------------------------------
        const _H('The precedence rule — all ten rows'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'Exactly one outcome renders, evaluated in order. Rows 2, 4 and 6 '
          'are D-30: existing data is never replaced by a state. A user who '
          'can already see rows does not lose them because a refresh failed or '
          'the network dropped.',
        ),
        const SizedBox(height: AppSpacing.space6),
        for (final row in _precedenceRows) ...[
          Text(
            '${row.$1}. ${row.$2}',
            style: AppTypography.fieldLabel.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space3),
          _Frame(child: _rowDemo(row.$3)),
          const SizedBox(height: AppSpacing.space6),
        ],
      ],
    );
  }

  static Widget _rowDemo(ScreenState<List<String>> state) {
    return ScreenStateBuilder<List<String>>(
      state: state,
      onRetry: () {},
      emptyTitle: 'No students yet',
      emptyMessage: 'Import a class list to get started.',
      emptyActionLabel: 'Import students',
      onEmptyAction: () {},
      filterDescription: 'Class 9-C',
      onClearFilter: () {},
      skeleton: const LoadingSkeleton.listRows(count: 2),
      data: (context, rows) => Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space5,
                vertical: AppSpacing.space3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r,
                      style: AppTypography.personName.copyWith(
                        color: context.tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const List<(int, String, ScreenState<List<String>>)> _precedenceRows = [
    (
      1,
      'Offline, no cached data -> OfflineState',
      ScreenState<List<String>>.loading(connection: NetworkStatus.offline),
    ),
    (
      2,
      'Offline, cached data exists -> the data, plus the offline indicator',
      ScreenState.data(_rows, connection: NetworkStatus.offline),
    ),
    (
      3,
      'Loading, no prior data -> LoadingSkeleton',
      ScreenState<List<String>>.loading(),
    ),
    (
      4,
      'Loading, prior data exists -> the prior data, refreshing in background',
      ScreenState<List<String>>.loading(previous: _rows),
    ),
    (
      5,
      'Error, no cached data -> ErrorState',
      ScreenState<List<String>>.failed(
        LoadFailure(message: 'The server did not respond in time.'),
      ),
    ),
    (
      6,
      'Error, cached data exists -> the data, plus a non-blocking notice',
      ScreenState.failed(
        LoadFailure(message: 'Could not refresh. Showing saved data.'),
        cached: _rows,
      ),
    ),
    (
      7,
      'Loaded, zero rows, filter active -> FilteredEmptyState',
      ScreenState.data(<String>[], isEmpty: true, hasFilter: true),
    ),
    (
      8,
      'Loaded, zero rows, no filter -> EmptyState',
      ScreenState.data(<String>[], isEmpty: true),
    ),
    (
      9,
      '/me returned 404 -> UnlinkedProfileState',
      ScreenState<List<String>>.failed(
        LoadFailure(kind: LoadFailureKind.notLinked),
      ),
    ),
    (
      10,
      'Otherwise -> the data',
      ScreenState.data(_rows),
    ),
  ];
}

/// Bordered frame so each state reads as occupying a screen region.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: child,
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.sectionHeading.copyWith(
          color: context.tokens.textPrimary,
        ),
      );
}

class _N extends StatelessWidget {
  const _N(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.bodyAdminMeta.copyWith(
          color: context.tokens.textSecondary,
        ),
      );
}

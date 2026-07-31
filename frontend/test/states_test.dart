import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/sizing.dart';
import 'package:smartems/core/theme/tokens.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/inline_alert.dart';
import 'package:smartems/core/widgets/states/empty_state.dart';
import 'package:smartems/core/widgets/states/error_state.dart';
import 'package:smartems/core/widgets/states/loading_skeleton.dart';
import 'package:smartems/core/widgets/states/screen_state.dart';
import 'package:smartems/core/widgets/states/screen_state_builder.dart';

import 'support/contrast.dart';

const _rows = ['Ayesha Khan', 'Bilal Mehmood'];

Widget host(
  Widget child, {
  bool dark = false,
  double width = 800,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: AppTheme.light(role: AppRole.teacher),
    darkTheme: AppTheme.dark(role: AppRole.teacher),
    // MediaQuery must be applied INSIDE MaterialApp: MaterialApp inserts its
    // own MediaQuery from the view, which would override an outer one.
    builder: (context, child) => reduceMotion
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          )
        : child!,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

/// A builder wired the way a real screen would wire it.
Widget subject(
  ScreenState<List<String>> state, {
  VoidCallback? onRetry,
  VoidCallback? onClearFilter,
  String? filterDescription,
  String? emptyActionLabel,
  VoidCallback? onEmptyAction,
}) {
  return ScreenStateBuilder<List<String>>(
    state: state,
    onRetry: onRetry ?? () {},
    emptyTitle: 'No students yet',
    emptyMessage: 'Import a class list to get started.',
    emptyActionLabel: emptyActionLabel,
    onEmptyAction: onEmptyAction,
    filterDescription: filterDescription,
    onClearFilter: onClearFilter,
    data: (context, rows) => Column(
      children: [for (final r in rows) Text(r)],
    ),
  );
}

void main() {
  // ==========================================================================
  // THE PRECEDENCE RULE — the highest-value tests in T4.
  // Each of the ten rows, asserted at the resolver AND through the widget.
  // ==========================================================================
  group('Precedence rule — all ten rows', () {
    test('row 1: offline, no cached data -> OfflineState', () {
      expect(
        resolveOutcome(const ScreenState<List<String>>.loading(
          connection: NetworkStatus.offline,
        )),
        ScreenOutcome.offlineState,
      );
    });

    test('row 2: offline, cached data exists -> data', () {
      expect(
        resolveOutcome(const ScreenState.data(
          _rows,
          connection: NetworkStatus.offline,
        )),
        ScreenOutcome.data,
      );
    });

    test('row 3: loading, no prior data -> LoadingSkeleton', () {
      expect(
        resolveOutcome(const ScreenState<List<String>>.loading()),
        ScreenOutcome.loadingSkeleton,
      );
    });

    test('row 4: loading, prior data exists -> data', () {
      expect(
        resolveOutcome(const ScreenState<List<String>>.loading(
          previous: _rows,
        )),
        ScreenOutcome.data,
      );
    });

    test('row 5: error, no cached data -> ErrorState', () {
      expect(
        resolveOutcome(
          const ScreenState<List<String>>.failed(LoadFailure(message: 'boom')),
        ),
        ScreenOutcome.errorState,
      );
    });

    test('row 6: error, cached data exists -> data', () {
      expect(
        resolveOutcome(
          const ScreenState.failed(
            LoadFailure(message: 'boom'),
            cached: _rows,
          ),
        ),
        ScreenOutcome.data,
      );
    });

    test('row 7: loaded, zero rows, filter active -> FilteredEmptyState', () {
      expect(
        resolveOutcome(const ScreenState.data(
          <String>[],
          isEmpty: true,
          hasFilter: true,
        )),
        ScreenOutcome.filteredEmptyState,
      );
    });

    test('row 8: loaded, zero rows, no filter -> EmptyState', () {
      expect(
        resolveOutcome(const ScreenState.data(<String>[], isEmpty: true)),
        ScreenOutcome.emptyState,
      );
    });

    test('row 9: /me 404 -> UnlinkedProfileState', () {
      expect(
        resolveOutcome(
          const ScreenState<List<String>>.failed(
            LoadFailure(kind: LoadFailureKind.notLinked),
          ),
        ),
        ScreenOutcome.unlinkedProfileState,
      );
    });

    test('row 10: otherwise -> data', () {
      expect(
        resolveOutcome(const ScreenState.data(_rows)),
        ScreenOutcome.data,
      );
    });

    test('row 7 is checked BEFORE row 8 (D-14)', () {
      // Same zero-row state; only hasFilter differs, and it must decide.
      const empty = ScreenState.data(<String>[], isEmpty: true);
      const filtered =
          ScreenState.data(<String>[], isEmpty: true, hasFilter: true);
      expect(resolveOutcome(empty), ScreenOutcome.emptyState);
      expect(resolveOutcome(filtered), ScreenOutcome.filteredEmptyState);
    });

    test('row 9 wins over rows 5 and 6 — notLinked is never an error', () {
      // Even with cached data, and even though status is error.
      expect(
        resolveOutcome(
          const ScreenState.failed(
            LoadFailure(kind: LoadFailureKind.notLinked),
            cached: _rows,
          ),
        ),
        ScreenOutcome.unlinkedProfileState,
      );
    });

    // ------------------------------------------------------------------
    // D-39 — emptiness is DERIVED by default, explicit only when it cannot be.
    // ------------------------------------------------------------------
    group('D-39: emptiness derivation', () {
      test('an empty List derives empty with NO isEmpty supplied', () {
        expect(
          resolveOutcome(const ScreenState.data(<String>[])),
          ScreenOutcome.emptyState,
        );
        expect(
          resolveOutcome(const ScreenState.data(_rows)),
          ScreenOutcome.data,
        );
      });

      test('derivation still respects the filter (row 7 before row 8)', () {
        expect(
          resolveOutcome(const ScreenState.data(<String>[], hasFilter: true)),
          ScreenOutcome.filteredEmptyState,
        );
      });

      test('an empty Map derives empty', () {
        expect(
          resolveOutcome(const ScreenState.data(<String, int>{})),
          ScreenOutcome.emptyState,
        );
        expect(
          resolveOutcome(const ScreenState.data(<String, int>{'a': 1})),
          ScreenOutcome.data,
        );
      });

      test('a HasRowCount type answers for itself', () {
        expect(
          resolveOutcome(
            const ScreenState.data(_FakePage(isEmptyResult: true)),
          ),
          ScreenOutcome.emptyState,
        );
        expect(
          resolveOutcome(
            const ScreenState.data(_FakePage(isEmptyResult: false)),
          ),
          ScreenOutcome.data,
        );
      });

      test('an explicit override beats derivation', () {
        expect(
          resolveOutcome(const ScreenState.data(_rows, isEmpty: true)),
          ScreenOutcome.emptyState,
        );
        expect(
          resolveOutcome(const ScreenState.data(<String>[], isEmpty: false)),
          ScreenOutcome.data,
        );
      });

      test('THROWS for an underivable type — it does NOT default to false',
          () {
        // The whole point of D-39. Defaulting to false would silently skip
        // rows 7 and 8 and render a blank area with no explanation.
        expect(
          () => resolveOutcome(const ScreenState.data(_Profile('Ayesha'))),
          throwsA(isA<StateError>()),
        );
      });

      test('the throw explains what to do about it', () {
        try {
          resolveOutcome(const ScreenState.data(_Profile('Ayesha')));
          fail('should have thrown');
        } on StateError catch (e) {
          expect(e.message, contains('D-39'));
          expect(e.message, contains('HasRowCount'));
          expect(e.message, contains('isEmpty: false'));
        }
      });

      test('an underivable type WITH an override is fine', () {
        expect(
          resolveOutcome(
            const ScreenState.data(_Profile('Ayesha'), isEmpty: false),
          ),
          ScreenOutcome.data,
        );
      });

      test('loaded with null data is empty, not a throw', () {
        expect(
          resolveOutcome(
            const ScreenState<List<String>>(status: ScreenStatus.loaded),
          ),
          ScreenOutcome.emptyState,
        );
      });

      test('derivation is never reached on loading, error or offline paths',
          () {
        // An underivable type must not throw while loading — otherwise a
        // profile screen would crash before it ever had data.
        expect(
          () => resolveOutcome(const ScreenState<_Profile>.loading()),
          returnsNormally,
        );
        expect(
          () => resolveOutcome(
            const ScreenState<_Profile>.failed(LoadFailure(message: 'x')),
          ),
          returnsNormally,
        );
        expect(
          () => resolveOutcome(
            const ScreenState<_Profile>.loading(
              connection: NetworkStatus.offline,
            ),
          ),
          returnsNormally,
        );
      });
    });

    test('exactly one outcome — the resolver is total', () {
      // Every combination of the inputs resolves, and never to null.
      for (final status in ScreenStatus.values) {
        for (final conn in NetworkStatus.values) {
          for (final hasData in [true, false]) {
            for (final hasFilter in [true, false]) {
              for (final isEmpty in [true, false]) {
                final s = ScreenState<List<String>>(
                  status: status,
                  data: hasData ? _rows : null,
                  failure: status == ScreenStatus.error
                      ? const LoadFailure(message: 'x')
                      : null,
                  connection: conn,
                  hasFilter: hasFilter,
                  isEmpty: isEmpty,
                );
                expect(resolveOutcome(s), isA<ScreenOutcome>());
              }
            }
          }
        }
      }
    });
  });

  // ==========================================================================
  // D-30 — existing data is NEVER replaced by a state.
  // ==========================================================================
  group('D-30: data always wins over a state when data exists', () {
    testWidgets('offline WITH cache renders rows, not OfflineState',
        (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState.data(
          _rows,
          connection: NetworkStatus.offline,
        ))),
      );

      expect(find.text('Ayesha Khan'), findsOneWidget);
      expect(find.text('Bilal Mehmood'), findsOneWidget);
      expect(find.byType(OfflineState), findsNothing);
      // ...but the offline indicator IS shown alongside (row 2).
      expect(find.byType(OfflineBanner), findsOneWidget);
    });

    testWidgets('a FAILED REFRESH over existing data does not blank the list',
        (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState.failed(
          LoadFailure(message: 'Gateway timeout'),
          cached: _rows,
        ))),
      );

      // The rows survive — this is the failure mode that makes an app feel
      // broken rather than slow.
      expect(find.text('Ayesha Khan'), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      // Non-blocking notice, carrying the backend message verbatim.
      expect(find.byType(InlineAlert), findsOneWidget);
      expect(find.text('Gateway timeout'), findsOneWidget);
    });

    testWidgets('loading over existing data keeps the rows and shows no '
        'skeleton', (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState<List<String>>.loading(
          previous: _rows,
        ))),
      );

      expect(find.text('Ayesha Khan'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      // No adornment for a background refresh — it must not flicker.
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.byType(InlineAlert), findsNothing);
    });

    test('adornment is only attached when the outcome IS data', () {
      expect(
        adornmentFor(const ScreenState<List<String>>.loading(
          connection: NetworkStatus.offline,
        )).any,
        isFalse,
        reason: 'OfflineState itself must not also carry an offline banner',
      );
      expect(
        adornmentFor(const ScreenState.data(
          _rows,
          connection: NetworkStatus.offline,
        )).showOfflineIndicator,
        isTrue,
      );
      expect(
        adornmentFor(const ScreenState.failed(
          LoadFailure(message: 'x'),
          cached: _rows,
        )).showRefreshFailedNotice,
        isTrue,
      );
    });
  });

  // ==========================================================================
  // Widget-level rendering of each state through the builder.
  // ==========================================================================
  group('The builder renders the right component', () {
    testWidgets('LoadingSkeleton, never a spinner', (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState<List<String>>.loading())),
      );
      expect(find.byType(LoadingSkeleton), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'skeletons, never a spinner',
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('OfflineState with no cache', (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState<List<String>>.loading(
          connection: NetworkStatus.offline,
        ))),
      );
      expect(find.byType(OfflineState), findsOneWidget);
    });

    testWidgets('ErrorState shows the backend message VERBATIM',
        (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState<List<String>>.failed(
          LoadFailure(message: 'Attendance for this date is locked.'),
        ))),
      );
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Attendance for this date is locked.'), findsOneWidget);
      expect(
        find.text('Something went wrong'),
        findsNothing,
        reason: 'a generic message discards what the backend told us',
      );
    });

    testWidgets('UnlinkedProfileState on a 404 from /me', (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState<List<String>>.failed(
          LoadFailure(kind: LoadFailureKind.notLinked),
        ))),
      );
      expect(find.byType(UnlinkedProfileState), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('EmptyState vs FilteredEmptyState are DISTINCT TYPES',
        (tester) async {
      await tester.pumpWidget(
        host(subject(const ScreenState.data(<String>[], isEmpty: true))),
      );
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(FilteredEmptyState), findsNothing);

      await tester.pumpWidget(
        host(subject(
          const ScreenState.data(<String>[], isEmpty: true, hasFilter: true),
          filterDescription: 'Class 9-C',
          onClearFilter: () {},
        )),
      );
      expect(find.byType(FilteredEmptyState), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });
  });

  // ==========================================================================
  // ErrorState retry escalation (D-11).
  // ==========================================================================
  group('ErrorState retry escalation (D-11)', () {
    testWidgets('the SECOND consecutive failure renders differently from the '
        'first', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        host(ErrorState(message: 'Timed out', onRetry: () => retries++)),
      );

      // First presentation.
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Retrying is not working'), findsNothing);

      // First retry.
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(retries, 1);
      expect(
        find.textContaining('Retrying is not working'),
        findsNothing,
        reason: 'one failure is not yet an escalation',
      );

      // Second retry — must NOT render identically to the first.
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(retries, 2);
      expect(
        find.textContaining('Retrying is not working'),
        findsOneWidget,
        reason: 'a button that visibly does nothing is worse than one that '
            'explains (D-11)',
      );
      expect(find.textContaining('connection'), findsOneWidget);
    });

    testWidgets('the label changes on the first retry, before escalation',
        (tester) async {
      await tester.pumpWidget(host(ErrorState(onRetry: () {})));
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('falls back to a neutral message when there is none',
        (tester) async {
      await tester.pumpWidget(host(ErrorState(onRetry: () {})));
      expect(find.text('The request did not complete.'), findsOneWidget);
    });
  });

  // ==========================================================================
  // Skeleton dimensions — a mismatch is a layout jump.
  // ==========================================================================
  group('Skeleton dimensions match the real content', () {
    testWidgets('a skeleton list row is at least listRowMinHeight',
        (tester) async {
      await tester.pumpWidget(
        host(const LoadingSkeleton.listRows(count: 3)),
      );

      final rows = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(LoadingSkeleton),
          matching: find.byType(Container),
        ),
      );
      expect(rows, isNotEmpty);

      // The constrained rows are the ones with a minHeight constraint.
      final constrained = rows.where(
        (c) => c.constraints?.minHeight == AppSizing.listRowMinHeight,
      );
      expect(
        constrained.length,
        3,
        reason: 'each skeleton row must match ListRow.minHeight '
            '(${AppSizing.listRowMinHeight}) or data arrival causes a jump',
      );
    });

    testWidgets('every variant renders its requested count', (tester) async {
      for (final variant in SkeletonVariant.values) {
        await tester.pumpWidget(
          host(LoadingSkeleton(variant: variant, count: 4)),
        );
        expect(find.byType(LoadingSkeleton), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$variant threw');
      }
    });

    test('a zero-row skeleton is unrepresentable', () {
      expect(
        () => LoadingSkeleton(variant: SkeletonVariant.listRows, count: 0),
        throwsAssertionError,
      );
    });
  });

  // ==========================================================================
  // Reduced motion (D-29 — an accessibility requirement, not an option).
  // ==========================================================================
  group('Reduced motion', () {
    testWidgets('shimmer is ABSENT when disableAnimations is set',
        (tester) async {
      await tester.pumpWidget(
        host(const LoadingSkeleton.listRows(), reduceMotion: true),
      );

      expect(
        find.descendant(
          of: find.byType(LoadingSkeleton),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
        reason: 'shimmer must stop under prefers-reduced-motion',
      );
      // ...but the skeleton itself is still there — static, not absent.
      expect(find.byType(LoadingSkeleton), findsOneWidget);
    });

    testWidgets('shimmer IS present by default', (tester) async {
      await tester.pumpWidget(host(const LoadingSkeleton.listRows()));
      expect(
        find.descendant(
          of: find.byType(LoadingSkeleton),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the shimmer animates opacity only, never layout (D-05)',
        (tester) async {
      await tester.pumpWidget(host(const LoadingSkeleton.listRows(count: 2)));
      final before = tester.getSize(find.byType(LoadingSkeleton));
      await tester.pump(const Duration(milliseconds: 450));
      final after = tester.getSize(find.byType(LoadingSkeleton));
      expect(
        after,
        before,
        reason: 'the skeleton changed size mid-animation — that is a layout '
            'animation, which D-05 prohibits',
      );
    });
  });

  // ==========================================================================
  // Not-an-error styling.
  // ==========================================================================
  group('Offline and Unlinked are NOT errors', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      final tokens = dark ? SmartEmsTokens.dark : SmartEmsTokens.light;

      testWidgets('OfflineState uses no danger token in $mode', (tester) async {
        await tester.pumpWidget(host(const OfflineState(), dark: dark));
        final icons = tester.widgetList<Icon>(find.byType(Icon));
        expect(icons, isNotEmpty);
        for (final i in icons) {
          expect(
            i.color,
            isNot(tokens.danger),
            reason: 'offline is a MODE, not a fault — styling it as a failure '
                'trains users to distrust a normal condition',
          );
        }
      });

      testWidgets('UnlinkedProfileState uses no danger token in $mode',
          (tester) async {
        await tester.pumpWidget(
          host(const UnlinkedProfileState(), dark: dark),
        );
        final icons = tester.widgetList<Icon>(find.byType(Icon));
        expect(icons, isNotEmpty);
        for (final i in icons) {
          expect(i.color, isNot(tokens.danger));
        }
      });

      testWidgets('ErrorState, by contrast, DOES use danger in $mode',
          (tester) async {
        await tester.pumpWidget(
          host(ErrorState(onRetry: () {}), dark: dark),
        );
        final icons = tester.widgetList<Icon>(find.byType(Icon));
        expect(
          icons.any((i) => i.color == tokens.danger),
          isTrue,
          reason: 'a real error should look like one — otherwise the '
              'not-an-error styling of the other two means nothing',
        );
      });
    }

    testWidgets('neither offers a retry — retrying cannot help', (tester) async {
      await tester.pumpWidget(host(const OfflineState()));
      expect(find.byType(AppButton), findsNothing);

      await tester.pumpWidget(host(const UnlinkedProfileState()));
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('UnlinkedProfileState points at the administrator',
        (tester) async {
      await tester.pumpWidget(host(const UnlinkedProfileState()));
      expect(find.textContaining('administrator'), findsOneWidget);
    });
  });

  // ==========================================================================
  // D-19 — no affordance without a backend.
  // ==========================================================================
  group('D-19: no false affordances', () {
    test('an EmptyState action needs BOTH a label and a callback', () {
      expect(
        () => EmptyState(
          title: 't',
          message: 'm',
          actionLabel: 'Do it',
        ),
        throwsAssertionError,
        reason: 'a label with no callback is a control that does nothing',
      );
      expect(
        () => EmptyState(title: 't', message: 'm', onAction: () {}),
        throwsAssertionError,
      );
    });

    testWidgets('EmptyState with no action renders no button', (tester) async {
      await tester.pumpWidget(
        host(const EmptyState(title: 'No notifications', message: 'm')),
      );
      expect(
        find.byType(AppButton),
        findsNothing,
        reason: 'an empty notifications list offers nothing, because there is '
            'nothing the user does about it',
      );
    });

    testWidgets('EmptyState with an action renders and fires it',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        host(EmptyState(
          title: 'No students yet',
          message: 'm',
          actionLabel: 'Import students',
          onAction: () => tapped++,
        )),
      );
      await tester.tap(find.text('Import students'));
      expect(tapped, 1);
    });

    testWidgets('FilteredEmptyState ALWAYS exposes a clear action',
        (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        host(FilteredEmptyState(
          filterDescription: 'Class 9-C',
          onClearFilter: () => cleared++,
        )),
      );
      expect(find.byType(AppButton), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      expect(cleared, 1);
      // And it states what was filtered on, so the user knows what to change.
      expect(find.textContaining('Class 9-C'), findsOneWidget);
    });

    test('a filterable builder must supply both filter fields', () {
      expect(
        () => ScreenStateBuilder<List<String>>(
          state: const ScreenState.data(_rows),
          onRetry: () {},
          emptyTitle: 't',
          emptyMessage: 'm',
          filterDescription: 'Class 9-C',
          data: (_, _) => const SizedBox.shrink(),
        ),
        throwsAssertionError,
        reason: 'FilteredEmptyState would be a dead end without a way out',
      );
    });
  });

  // ==========================================================================
  // Contrast for the new pairings introduced by T4.
  // ==========================================================================
  group('T4 contrast pairings', () {
    test('escalation notice text on warningBg', () {
      for (final t in [SmartEmsTokens.light, SmartEmsTokens.dark]) {
        expect(
          contrastRatio(t.warningTextOnBg, t.warningBg),
          greaterThanOrEqualTo(aaText),
        );
      }
    });

    test('OfflineBanner text and icon on surfaceSunken', () {
      for (final t in [SmartEmsTokens.light, SmartEmsTokens.dark]) {
        expect(
          contrastRatio(t.textPrimary, t.surfaceSunken),
          greaterThanOrEqualTo(aaText),
        );
        expect(
          contrastRatio(t.textSecondary, t.surfaceSunken),
          greaterThanOrEqualTo(aaNonText),
        );
      }
    });

    test('state icons against the page', () {
      for (final t in [SmartEmsTokens.light, SmartEmsTokens.dark]) {
        // Icons are non-text, 3:1.
        // NOTE: textMuted is deliberately NOT tested here — it measures
        // 2.39:1 on surface and is not valid for an icon. The state icons use
        // textSecondary instead.
        expect(contrastRatio(t.textSecondary, t.surface),
            greaterThanOrEqualTo(aaNonText));
        expect(contrastRatio(t.info, t.surface),
            greaterThanOrEqualTo(aaNonText));
        expect(contrastRatio(t.danger, t.surface),
            greaterThanOrEqualTo(aaNonText));
        expect(contrastRatio(t.textSecondary, t.surface),
            greaterThanOrEqualTo(aaNonText));
      }
    });

    test('skeleton blocks are visible against their surface', () {
      for (final t in [SmartEmsTokens.light, SmartEmsTokens.dark]) {
        expect(
          contrastRatio(t.surfaceSunken, t.surface),
          greaterThan(1.05),
          reason: 'a skeleton block invisible against its surface is not a '
              'skeleton',
        );
      }
    });
  });

  // ==========================================================================
  // Layout — the standing Phase 6 requirement.
  // ==========================================================================
  group('No overflow at 360, 768 and 1366px', () {
    for (final width in <double>[360, 768, 1366]) {
      testWidgets('every state renders clean at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final states = <Widget>[
          const LoadingSkeleton.listRows(count: 2),
          const LoadingSkeleton.cards(count: 2),
          const LoadingSkeleton.tableRows(count: 2),
          const LoadingSkeleton.statCards(count: 4),
          const EmptyState(title: 'No students yet', message: 'Import a list.'),
          FilteredEmptyState(
            filterDescription: 'Class 9-C',
            onClearFilter: () {},
          ),
          ErrorState(message: 'A fairly long backend message.', onRetry: () {}),
          const OfflineState(),
          const UnlinkedProfileState(),
          const OfflineBanner(),
        ];

        for (final s in states) {
          await tester.pumpWidget(host(s, width: width));
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${s.runtimeType} overflowed at ${width.toInt()}px',
          );
        }
      });
    }
  });

  // ==========================================================================
  // No snackbar / no timed dismissal — same contract as InlineAlert.
  // ==========================================================================
  group('States are persistent, never timed', () {
    testWidgets('no state is a SnackBar or an overlay', (tester) async {
      for (final s in <Widget>[
        const EmptyState(title: 't', message: 'm'),
        ErrorState(onRetry: () {}),
        const OfflineState(),
        const UnlinkedProfileState(),
        const OfflineBanner(),
      ]) {
        await tester.pumpWidget(host(s));
        expect(find.byType(SnackBar), findsNothing);
      }
    });

    testWidgets('states survive the passage of time', (tester) async {
      await tester.pumpWidget(host(const OfflineState()));
      expect(find.byType(OfflineState), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(OfflineState), findsOneWidget);
    });
  });

  group('Typography use is correct per D-33', () {
    testWidgets('state titles use cardHeading, bodies use bodyAdminMeta',
        (tester) async {
      await tester.pumpWidget(
        host(const EmptyState(title: 'No students yet', message: 'Import.')),
      );
      final title = tester.widget<Text>(find.text('No students yet'));
      expect(title.style?.fontSize, AppTypography.cardHeading.fontSize);
      final body = tester.widget<Text>(find.text('Import.'));
      expect(body.style?.fontSize, AppTypography.bodyAdminMeta.fontSize);
    });
  });
}

// --- D-39 fixtures ---------------------------------------------------------

/// Stands in for the paged result type T6 will introduce.
class _FakePage implements HasRowCount {
  const _FakePage({required this.isEmptyResult});

  @override
  final bool isEmptyResult;
}

/// A single object that is never "empty" — a profile, a settings record. The
/// resolver cannot inspect it, so it must be told.
class _Profile {
  const _Profile(this.name);

  final String name;
}

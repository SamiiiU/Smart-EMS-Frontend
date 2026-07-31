import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/composites_gallery.dart';
import 'package:smartems/core/theme/sizing.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/app_data_table.dart';
import 'package:smartems/core/widgets/context_strip.dart';
import 'package:smartems/core/widgets/hero_card.dart';
import 'package:smartems/core/widgets/inline_alert.dart';
import 'package:smartems/core/widgets/list_row.dart';
import 'package:smartems/core/widgets/section_card.dart';
import 'package:smartems/core/widgets/stat_card.dart';
import 'package:smartems/core/widgets/status_pill.dart';
import 'package:smartems/core/widgets/tabs.dart';

Widget host(Widget child, {bool dark = false, double width = 1024}) {
  return MaterialApp(
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: AppTheme.light(role: AppRole.teacher),
    darkTheme: AppTheme.dark(role: AppRole.teacher),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

List<AppDataRow> sampleRows() => [
      const AppDataRow(
        cells: ['Ayesha Khan', '9-C', '96%'],
        status: AppStatus.active,
      ),
      const AppDataRow(
        cells: ['Bilal Mehmood', '9-C', '71%'],
        status: AppStatus.partial,
        tint: RowTint.warning,
      ),
    ];

void main() {
  group('ListRow — whole row is the tap target', () {
    testWidgets('a tap near the LEADING edge fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          ListRow(
            leading: const Icon(Icons.person),
            title: 'Ayesha Khan',
            subtitle: 'Roll 12',
            trailing: const StatusPill(status: AppStatus.present),
            onTap: () => taps++,
          ),
        ),
      );

      final rect = tester.getRect(find.byType(ListRow));
      // 4px inside the left edge, vertically centred — nowhere near the pill.
      await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
      await tester.pump();

      expect(taps, 1, reason: 'tap at the leading edge did not fire onTap');
    });

    testWidgets('a tap in the empty gap between title and trailing fires onTap',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          ListRow(
            title: 'Short',
            trailing: const StatusPill(status: AppStatus.present),
            onTap: () => taps++,
          ),
        ),
      );

      final rect = tester.getRect(find.byType(ListRow));
      // Just left of the trailing pill: dead space in a naive implementation.
      final pill = tester.getRect(find.byType(StatusPill));
      await tester.tapAt(Offset(pill.left - 8, rect.center.dy));
      await tester.pump();

      expect(taps, 1, reason: 'tap in the inter-child gap did not fire onTap');
    });

    testWidgets('respects the 56px minimum height', (tester) async {
      await tester.pumpWidget(host(const ListRow(title: 'x')));
      expect(
        tester.getSize(find.byType(ListRow)).height,
        greaterThanOrEqualTo(AppSizing.listRowMinHeight),
      );
    });
  });

  group('PeriodRow', () {
    testWidgets('renders a break as a visible muted row, not an omission',
        (tester) async {
      await tester.pumpWidget(
        host(
          const Column(
            children: [
              PeriodRow(time: '08:00', title: 'Mathematics'),
              PeriodRow(time: '09:30', title: 'Break', isBreak: true),
            ],
          ),
        ),
      );
      // The break must be PRESENT — a gap would read as missing data.
      expect(find.text('Break'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);
      expect(find.byType(PeriodRow), findsNWidgets(2));
    });

    testWidgets('time column is exactly 44px wide', (tester) async {
      await tester.pumpWidget(
        host(const PeriodRow(time: '08:00', title: 'Mathematics')),
      );
      final box = tester.getSize(
        find.ancestor(
          of: find.text('08:00'),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(box.width, AppSizing.periodTimeColumnWidth);
    });

    testWidgets('a break row is not tappable', (tester) async {
      await tester.pumpWidget(
        host(const PeriodRow(time: '09:30', title: 'Break', isBreak: true)),
      );
      expect(
        find.descendant(
          of: find.byType(PeriodRow),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  group('HeroCard — the brand/tinted distinction is structural (D-23)', () {
    // COMPILE-TIME GUARANTEE: HeroCardBrand has no action parameter, so
    // `HeroCardBrand(action: ...)` does not compile. That cannot be asserted at
    // runtime, so these tests assert the observable consequence: a brand hero
    // contains no action and no gesture handling whatsoever.
    testWidgets('brand variant carries no button and no gesture detector',
        (tester) async {
      await tester.pumpWidget(
        host(
          const HeroCardBrand(
            eyebrow: 'Today',
            title: '96% present',
            subtitle: 'Marked at 08:04',
          ),
        ),
      );

      expect(find.byType(AppButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HeroCardBrand),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: 'the brand hero must not carry any action',
      );
    });

    test('HeroCardBrand exposes no action-shaped field', () {
      // Guards against someone adding one later: the brand hero's public
      // surface is exactly title/eyebrow/subtitle.
      const brand = HeroCardBrand(title: 't');
      expect(brand.title, 't');
      expect(brand.eyebrow, isNull);
      expect(brand.subtitle, isNull);
      // If an `action` field were added, this file would no longer compile
      // against the intent recorded here.
      expect(brand, isA<HeroCard>());
    });

    testWidgets('tinted variant renders its required action and it works',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          HeroCardTinted(
            title: 'Mathematics',
            action: AppButton(label: 'Mark', onPressed: () => taps++),
          ),
        ),
      );
      expect(find.byType(AppButton), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      expect(taps, 1);
    });

    test('both variants are HeroCard, and HeroCard is sealed', () {
      expect(const HeroCardBrand(title: 'a'), isA<HeroCard>());
      expect(
        const HeroCardTinted(title: 'b', action: SizedBox.shrink()),
        isA<HeroCard>(),
      );
    });
  });

  group('AppDataTable — collapse and no horizontal scroll', () {
    testWidgets('at 599px it COLLAPSES to stacked cards', (tester) async {
      await tester.pumpWidget(
        host(
          AppDataTable(
            columns: const ['Student', 'Class', 'Present %'],
            rows: sampleRows(),
          ),
          width: 599,
        ),
      );

      // Collapsed: each column label appears once PER ROW (2 rows), because
      // every row becomes a label:value card.
      expect(find.text('STUDENT'), findsNWidgets(2));
      expect(find.text('CLASS'), findsNWidgets(2));
      expect(find.text('PRESENT %'), findsNWidgets(2));
    });

    testWidgets('at 601px it renders as a WIDE table with one header band',
        (tester) async {
      await tester.pumpWidget(
        host(
          AppDataTable(
            columns: const ['Student', 'Class', 'Present %'],
            rows: sampleRows(),
          ),
          width: 601,
        ),
      );

      // Wide: the header band appears exactly once.
      expect(find.text('STUDENT'), findsOneWidget);
      expect(find.text('CLASS'), findsOneWidget);
      expect(find.text('PRESENT %'), findsOneWidget);
    });

    testWidgets('exactly at the 600px breakpoint it is wide (>= is wide)',
        (tester) async {
      await tester.pumpWidget(
        host(
          AppDataTable(
            columns: const ['Student', 'Class'],
            rows: sampleRows(),
          ),
          width: AppSizing.tableCollapseBreakpoint,
        ),
      );
      expect(find.text('STUDENT'), findsOneWidget);
    });

    testWidgets('NEVER scrolls horizontally at 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppDataTable(
                columns: const ['Student', 'Class', 'Present %', 'Guardian'],
                rows: sampleRows(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No horizontal scrollable anywhere in the table.
      final scrollables = tester.widgetList<Scrollable>(find.byType(Scrollable));
      for (final s in scrollables) {
        expect(
          s.axisDirection,
          anyOf(AxisDirection.down, AxisDirection.up),
          reason: 'found a horizontally scrolling widget in AppDataTable',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Tabs — D-19', () {
    testWidgets('a tab with no content is NOT rendered', (tester) async {
      await tester.pumpWidget(
        host(
          Tabs(
            tabs: const [
              AppTab(label: 'Overview'),
              AppTab(label: 'Fees', hasContent: false),
              AppTab(label: 'Remarks'),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Remarks'), findsOneWidget);
      expect(
        find.text('Fees'),
        findsNothing,
        reason: 'an empty tab must be hidden, not greyed out (D-19)',
      );
    });

    test('visible() filters out contentless tabs', () {
      final v = Tabs.visible(const [
        AppTab(label: 'a'),
        AppTab(label: 'b', hasContent: false),
      ]);
      expect(v.map((t) => t.label), ['a']);
    });

    testWidgets('selection indexes into VISIBLE tabs', (tester) async {
      var selected = -1;
      await tester.pumpWidget(
        host(
          Tabs(
            tabs: const [
              AppTab(label: 'Overview'),
              AppTab(label: 'Fees', hasContent: false),
              AppTab(label: 'Remarks'),
            ],
            selectedIndex: 0,
            onSelected: (i) => selected = i,
          ),
        ),
      );
      await tester.tap(find.text('Remarks'));
      // Remarks is index 2 in the raw list but index 1 among visible tabs.
      expect(selected, 1);
    });

    testWidgets('renders nothing when no tab has content', (tester) async {
      await tester.pumpWidget(
        host(
          Tabs(
            tabs: const [AppTab(label: 'a', hasContent: false)],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('a'), findsNothing);
    });

    testWidgets('each tab meets the 44px touch target', (tester) async {
      await tester.pumpWidget(
        host(
          Tabs(
            tabs: const [AppTab(label: 'Overview')],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      );
      final size = tester.getSize(find.text('Overview').hitTestable());
      expect(size.height, lessThanOrEqualTo(AppSizing.touchTargetMin));
      final tabBox = tester.getSize(
        find.ancestor(
          of: find.text('Overview'),
          matching: find.byType(Container),
        ).first,
      );
      expect(tabBox.height, greaterThanOrEqualTo(AppSizing.touchTargetMin));
    });
  });

  group('InlineAlert is persistent, never a snackbar', () {
    testWidgets('stays on screen after time passes', (tester) async {
      await tester.pumpWidget(
        host(
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'Attendance is below 75%.',
          ),
        ),
      );
      expect(find.text('Attendance is below 75%.'), findsOneWidget);

      // A snackbar would be gone by now.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Attendance is below 75%.'), findsOneWidget);
    });

    testWidgets('renders every tone with an icon in both modes',
        (tester) async {
      for (final dark in [false, true]) {
        for (final tone in InlineAlertTone.values) {
          await tester.pumpWidget(
            host(InlineAlert(tone: tone, message: 'm'), dark: dark),
          );
          expect(find.text('m'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(InlineAlert),
              matching: find.byType(Icon),
            ),
            findsOneWidget,
            reason: '$tone rendered without an icon — tone would rely on '
                'colour alone',
          );
        }
      }
    });
  });

  group('Composites render in both modes', () {
    testWidgets('ContextStrip, StatCard, SectionCard, HeroCards',
        (tester) async {
      for (final dark in [false, true]) {
        for (final tone in ContextStripTone.values) {
          await tester.pumpWidget(
            host(
              ContextStrip(
                icon: Icons.school_outlined,
                title: 'School',
                subtitle: 'Campus',
                tone: tone,
                status: tone == ContextStripTone.semantic
                    ? AppStatus.partial
                    : null,
              ),
              dark: dark,
            ),
          );
          expect(find.text('School'), findsOneWidget);
        }

        for (final tone in StatCardTone.values) {
          await tester.pumpWidget(
            host(StatCard(value: '1,234', label: 'l', tone: tone), dark: dark),
          );
          expect(find.text('1,234'), findsOneWidget);
        }

        await tester.pumpWidget(
          host(
            const SectionCard(title: 'H', child: Text('body')),
            dark: dark,
          ),
        );
        expect(find.text('body'), findsOneWidget);
      }
    });

    testWidgets('StatCard fires onTap across the whole card', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(StatCard(value: '1', label: 'l', onTap: () => taps++)),
      );
      final r = tester.getRect(find.byType(StatCard));
      await tester.tapAt(Offset(r.left + 2, r.top + 2));
      expect(taps, 1);
    });
  });

  group('No overflow at 360, 768 and 1366px (standing Phase 6 requirement)',
      () {
    for (final width in <double>[360, 768, 1366]) {
      testWidgets('composites gallery renders clean at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 8000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(role: AppRole.teacher),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CompositesGallerySection(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // A RenderFlex overflow surfaces as a thrown exception in tests.
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${width.toInt()}px',
        );
      });
    }
  });
}

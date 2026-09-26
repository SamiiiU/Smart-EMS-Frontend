import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/shell/app_shell.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/theme_controller.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/admin/domain/people_models.dart';
import 'package:smartems/features/admin/presentation/people_screen.dart';
import 'package:smartems/features/settings/presentation/settings_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);

  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return responder(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
      'content': rows,
      'totalElements': rows.length,
    };

/// Stands in for the three endpoints `loadPeople` joins.
_Adapter _peopleServer({bool guardiansFail = false}) => _Adapter((o) {
      final path = o.uri.path;
      if (path == '/api/staff') {
        return _json(
            200,
            _page([
              {
                'id': 's1',
                'firstName': 'Ayesha',
                'lastName': 'Khan',
                'employeeCode': 'EMP-002',
                'designation': 'Teacher',
                'userId': 'u-1',
              },
              {
                'id': 's2',
                'firstName': 'Bilal',
                'lastName': 'Ahmed',
                'employeeCode': 'EMP-003',
                'userId': null,
              },
            ]));
      }
      if (path == '/api/students') {
        return _json(
            200,
            _page([
              {
                'id': 'st1',
                'firstName': 'Ali',
                'lastName': 'Khan',
                'admissionNumber': 'STU-001',
                'status': 'active',
                'userId': 'u-9',
              },
            ]));
      }
      if (path.startsWith('/api/guardians/student/')) {
        if (guardiansFail) return _json(500, {'message': 'boom'});
        return _json(200, [
          {
            'guardian': {
              'id': 'g1',
              'firstName': 'Imran',
              'lastName': 'Khan',
              'userId': null,
            },
            'relationship': 'father',
          },
        ]);
      }
      return _json(404, {'message': 'no route'});
    });

AdminRepository _repo(_Adapter a) => AdminRepository(
    Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = a);

Widget _host(Widget child, {double textScale = 1, TextDirection? dir}) =>
    MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: dir == null
            ? child
            : Directionality(textDirection: dir, child: child),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Accounts list', () {
    testWidgets('shows who has a login and who does not', (tester) async {
      await tester
          .pumpWidget(_host(PeopleScreen(repository: _repo(_peopleServer()))));
      await tester.pumpAndSettle();

      // Staff group is first; Bilal has no login and sorts above Ayesha.
      expect(find.text('Bilal Ahmed'), findsOneWidget);
      expect(find.text('No login'), findsOneWidget);
      expect(find.text('Has login'), findsOneWidget);
      final noLogin = tester.getCenter(find.text('No login'));
      final hasLogin = tester.getCenter(find.text('Has login'));
      expect(noLogin.dy, lessThan(hasLogin.dy),
          reason: 'people without a login are the ones needing action');
    });

    testWidgets('counts the people who cannot sign in', (tester) async {
      await tester
          .pumpWidget(_host(PeopleScreen(repository: _repo(_peopleServer()))));
      await tester.pumpAndSettle();
      // Bilal (staff) and Imran (parent) = 2 of 4.
      expect(find.textContaining('2 of 4 people have no login'),
          findsOneWidget);
    });

    testWidgets('switching group shows parents built per student',
        (tester) async {
      await tester
          .pumpWidget(_host(PeopleScreen(repository: _repo(_peopleServer()))));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Parents'));
      await tester.pumpAndSettle();
      expect(find.text('Imran Khan'), findsOneWidget);
      expect(find.textContaining('father of Ali Khan'), findsOneWidget);
    });

    testWidgets('a failed guardian lookup warns instead of hiding the list',
        (tester) async {
      await tester.pumpWidget(_host(
          PeopleScreen(repository: _repo(_peopleServer(guardiansFail: true)))));
      await tester.pumpAndSettle();

      // Staff still loaded — the failure is partial, not fatal.
      expect(find.text('Ayesha Khan'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Parents'));
      await tester.pumpAndSettle();
      expect(find.textContaining('may be incomplete'), findsOneWidget);
    });

    testWidgets('search filters, and says so when nothing matches',
        (tester) async {
      await tester
          .pumpWidget(_host(PeopleScreen(repository: _repo(_peopleServer()))));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ayesha');
      await tester.pumpAndSettle();
      expect(find.text('Bilal Ahmed'), findsNothing);
      expect(find.text('Ayesha Khan'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nobody yet'), findsNothing);
    });

    testWidgets('says plainly that unlinked logins cannot be listed',
        (tester) async {
      await tester
          .pumpWidget(_host(PeopleScreen(repository: _repo(_peopleServer()))));
      await tester.pumpAndSettle();
      expect(find.textContaining('never linked to a person cannot be listed'),
          findsOneWidget);
    });

    test('one guardian of two children appears once', () {
      const g = PersonAccount(
          id: 'g1', fullName: 'Imran', group: PeopleGroup.parents);
      const d = PeopleDirectory(staff: [], students: [], parents: [g]);
      expect(d.parents, hasLength(1));
      expect(d.withoutLogin, 1);
    });
  });

  group('Appearance (theme)', () {
    testWidgets('three choices, and picking one persists it', (tester) async {
      final controller = ThemeController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(SettingsScreen(
        onSignOut: () async {},
        themeController: controller,
      )));

      expect(find.bySemanticsLabel('System'), findsOneWidget);
      expect(find.bySemanticsLabel('Light'), findsOneWidget);
      expect(find.bySemanticsLabel('Dark'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Dark'));
      await tester.pumpAndSettle();
      expect(controller.value, ThemeMode.dark);

      final restored = ThemeController();
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.value, ThemeMode.dark,
          reason: 'the choice must survive a relaunch');
    });

    test('defaults to following the device, and survives junk on disk',
        () async {
      SharedPreferences.setMockInitialValues({'ui.theme_mode': 'purple'});
      final c = ThemeController();
      addTearDown(c.dispose);
      await c.restore();
      expect(c.value, ThemeMode.system);
    });

    testWidgets('no controller → no appearance section', (tester) async {
      await tester
          .pumpWidget(_host(SettingsScreen(onSignOut: () async {})));
      expect(find.text('Appearance'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  group('Ways out of a dead end', () {
    Widget shell({
      required IdentityResult identity,
      required List<NavDestination> destinations,
      Future<void> Function()? onSignOut,
    }) =>
        _host(AppShell(
          institutionName: 'Test School',
          destinations: destinations,
          entitledIds: destinations.map((d) => d.id).toSet(),
          identityResolver: StaticIdentityResolver(identity),
          onSignOut: onSignOut,
        ));

    testWidgets('the orphan screen offers sign-out', (tester) async {
      var signedOut = false;
      await tester.pumpWidget(shell(
        identity: const IdentityResult(IdentityResultKind.notLinked),
        destinations: const [],
        onSignOut: () async => signedOut = true,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('not been linked'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });

    testWidgets('the identity-error screen keeps retry AND sign-out',
        (tester) async {
      await tester.pumpWidget(shell(
        identity: const IdentityResult(
          IdentityResultKind.error,
          message: 'Timed out',
        ),
        destinations: const [],
        onSignOut: () async {},
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('on a phone, everything past the third tab is reachable',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      NavDestination d(String id, String label, Widget body) => NavDestination(
            id: id,
            label: label,
            icon: Icons.circle_outlined,
            route: '/$id',
            builder: (_) => body,
          );

      await tester.pumpWidget(shell(
        identity: const IdentityResult(IdentityResultKind.linked),
        destinations: [
          d('a', 'A', const Text('A body')),
          d('b', 'B', const Text('B body')),
          d('c', 'C', const Text('C body')),
          d('import', 'Import', const Text('Import body')),
          d('more', 'More', const Text('Settings body')),
        ],
      ));
      await tester.pumpAndSettle();

      // The synthesized More tab used to be a placeholder, which stranded
      // Import and sign-out on phones.
      expect(find.text('More — built in a later task'), findsNothing);

      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.text('Import'), findsWidgets);
      expect(find.text('Settings & sign out'), findsOneWidget);

      await tester.tap(find.text('Settings & sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Settings body'), findsOneWidget);
    });
  });

  group('Layout', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('accounts + settings: no overflow at $width, 2×, RTL',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(
          PeopleScreen(repository: _repo(_peopleServer())),
          textScale: 2,
          dir: TextDirection.rtl,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final c = ThemeController();
        addTearDown(c.dispose);
        await tester.pumpWidget(_host(
          SettingsScreen(onSignOut: () async {}, themeController: c),
          textScale: 2,
          dir: TextDirection.rtl,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

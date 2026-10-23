import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/nav_destination.dart';
import 'package:smartems/core/shell/role_destinations.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/admin/data/ownership_repository.dart';
import 'package:smartems/features/settings/presentation/settings_screen.dart';

/// Hard-QA fixes BUG-QA-06, -08 (campus scoping) and -09.
NavDestination _d(String id) => NavDestination(
  id: id,
  label: id,
  icon: Icons.circle,
  route: '/',
  builder: (_) => const SizedBox(),
);

class _Server implements HttpClientAdapter {
  _Server(this.routes);
  final Map<String, (int, Object)> routes;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    final (status, body) = routes[o.path] ?? (404, const {});
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(Map<String, (int, Object)> routes) =>
    Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _Server(routes);

void main() {
  group('BUG-QA-09: institution-wide destinations', () {
    final all = [_d('students'), _d('import'), _d('more')];

    test('campus-scoped student.manage does NOT offer Import', () {
      final ids = RoleDestinations.visibleFor(all, {
        'student.manage',
        'student.view',
      }, institutionWide: const {}).map((d) => d.id);
      expect(ids, ['students', 'more']);
    });

    test('institution-wide student.manage or staff.manage offers Import', () {
      for (final p in ['student.manage', 'staff.manage']) {
        final ids = RoleDestinations.visibleFor(
          all,
          {'student.manage', p},
          institutionWide: {p},
        ).map((d) => d.id);
        expect(ids, contains('import'), reason: p);
      }
    });

    test(
      'unknown grant detail keeps the previous behaviour (server stays the authority)',
      () {
        final ids = RoleDestinations.visibleFor(all, {
          'student.manage',
        }).map((d) => d.id);
        expect(ids, contains('import'));
      },
    );
  });

  group('BUG-QA-08: fee screens use only campuses with fee.manage', () {
    test('Teacher@A + Finance@B → only B', () async {
      final repo = AdminRepository(
        _dio({
          '/api/campuses/mine': (
            200,
            {
              'campuses': [
                {
                  'id': 'A',
                  'name': 'A',
                  'permissions': ['attendance.mark', 'student.view'],
                },
                {
                  'id': 'B',
                  'name': 'B',
                  'permissions': ['fee.manage', 'fee.view'],
                },
              ],
            },
          ),
        }),
      );
      expect(await repo.loadCampusIdsWith('fee.manage'), ['B']);
      expect(await repo.loadCampusIds(), [
        'A',
        'B',
      ], reason: 'the unfiltered list is unchanged');
    });
  });

  group('BUG-QA-06: Ownership transfer entry', () {
    Future<void> pump(
      WidgetTester tester,
      Map<String, (int, Object)> routes,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: Scaffold(
            body: OwnershipTransferEntry(
              repository: OwnershipRepository(_dio(routes)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final teacherMe = (
      200,
      {
        'grants': [
          {'role': 'teacher', 'campusId': 'A'},
        ],
      },
    );

    testWidgets('hidden for a teacher with no pending transfer', (
      tester,
    ) async {
      await pump(tester, {
        '/auth/me': teacherMe,
        '/api/institution/ownership-transfer': (200, const {}),
      });
      expect(find.byKey(const Key('settings-ownership')), findsNothing);
    });

    testWidgets('shown to the institution-wide owner', (tester) async {
      await pump(tester, {
        '/auth/me': (
          200,
          {
            'grants': [
              {'role': 'owner', 'campusId': null},
            ],
          },
        ),
      });
      expect(find.byKey(const Key('settings-ownership')), findsOneWidget);
    });

    testWidgets(
      'an owner grant scoped to ONE campus is not the institution owner',
      (tester) async {
        await pump(tester, {
          '/auth/me': (
            200,
            {
              'grants': [
                {'role': 'owner', 'campusId': 'A'},
              ],
            },
          ),
          '/api/institution/ownership-transfer': (200, const {}),
        });
        expect(find.byKey(const Key('settings-ownership')), findsNothing);
      },
    );

    testWidgets('shown to a non-owner who has a pending transfer to accept', (
      tester,
    ) async {
      await pump(tester, {
        '/auth/me': teacherMe,
        '/api/institution/ownership-transfer': (
          200,
          {'id': 't1', 'initiatedBy': 'o1', 'targetUserId': 'me'},
        ),
      });
      expect(find.byKey(const Key('settings-ownership')), findsOneWidget);
    });

    testWidgets('hidden on failure (the server enforces the rule anyway)', (
      tester,
    ) async {
      await pump(tester, {
        '/auth/me': (500, const {}),
        '/api/institution/ownership-transfer': (500, const {}),
      });
      expect(find.byKey(const Key('settings-ownership')), findsNothing);
    });
  });
}

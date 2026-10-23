import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/identity_resolver.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/adaptive_data_view.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/admin/presentation/people_screen.dart';

/// M5 Accounts on AdaptiveDataView: "Campus roles" is offered only where the
/// server (ADR-011, CampusGrantService) would allow administering campus
/// grants, never on the viewer's own row. Synthetic data; the transport
/// records every request and NO mutation (POST/PUT/PATCH/DELETE) may occur.

class _Server implements HttpClientAdapter {
  final requests = <String>[];

  /// Campus grants the server reports per user id (GET only).
  final grantsByUser = <String, List<Map<String, dynamic>>>{};

  ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add('${o.method} ${o.uri.path}');
    final path = o.uri.path;
    if (path == '/api/staff') {
      return _json(200, {
        'content': [
          {
            'id': 's-self',
            'firstName': 'Viewer',
            'lastName': 'Self',
            'employeeCode': 'EMP-001',
            'designation': 'Administrator',
            'userId': 'u-self',
          },
          {
            'id': 's-2',
            'firstName': 'Bushra',
            'lastName': 'Teacher',
            'employeeCode': 'EMP-002',
            'designation': 'Teacher',
            'userId': 'u-2',
          },
          {
            'id': 's-3',
            'firstName': 'Nadia',
            'lastName': 'Nologin',
            'employeeCode': 'EMP-003',
            'designation': 'Clerk',
            'userId': null,
          },
        ],
        'totalElements': 3,
      });
    }
    if (path == '/api/students') {
      return _json(200, {
        'content': [
          {
            'id': 'st1',
            'firstName': 'Ali',
            'lastName': 'Khan',
            'admissionNumber': 'STU-001',
            'status': 'active',
            'userId': 'u-9',
          },
        ],
        'totalElements': 1,
      });
    }
    if (path == '/api/guardians')
      return _json(200, {'content': [], 'totalElements': 0});
    if (path.endsWith('/campus-grants')) {
      final user = path.split('/')[3];
      return _json(200, grantsByUser[user] ?? const []);
    }
    return _json(404, {'message': 'no route'});
  }

  @override
  void close({bool force = false}) {}
}

IdentityResult _who(
  String role, {
  String? campusId,
  List<String> permissions = const [],
  bool known = true,
}) => IdentityResult(
  IdentityResultKind.linked,
  roles: [role],
  userId: 'u-self',
  tenantId: 't',
  grants: [
    GrantScope(role: role, campusId: campusId, permissions: permissions),
  ],
  permissions: permissions,
  permissionsKnown: known,
);

Future<_Server> _pump(
  WidgetTester tester,
  IdentityResult? viewer, {
  double width = 1440,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server = _Server();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: PeopleScreen(
        repository: AdminRepository(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
        ),
        currentIdentity: viewer == null ? null : () => viewer,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

void _noMutations(_Server s) => expect(
  s.requests.where((r) => !r.startsWith('GET ')),
  isEmpty,
  reason: 'no role mutation may be sent',
);

const _other = Key('campus-roles-s-2');
const _self = Key('campus-roles-s-self');
const _nologin = Key('campus-roles-s-3');

void main() {
  group('who is offered "Campus roles" (mirrors CampusGrantService)', () {
    final cases = <String, (IdentityResult?, bool)>{
      'Institution Owner (institution-wide)': (
        _who('institution_owner', permissions: ['user.manage', 'staff.manage']),
        true,
      ),
      'Owner (legacy role name)': (
        _who('owner', permissions: ['user.manage']),
        true,
      ),
      'Institution Admin (institution-wide)': (
        _who('institution_admin', permissions: ['user.manage', 'staff.manage']),
        true,
      ),
      'Campus Admin with user.manage on its campus': (
        _who(
          'campus_admin',
          campusId: 'c1',
          permissions: ['user.manage', 'staff.manage'],
        ),
        true,
      ),
      'Campus Admin WITHOUT user.manage': (
        _who('campus_admin', campusId: 'c1', permissions: ['staff.manage']),
        false,
      ),
      'Teacher': (
        _who('teacher', campusId: 'c1', permissions: ['attendance.mark']),
        false,
      ),
      'Finance Staff': (
        _who(
          'finance_staff',
          campusId: 'c1',
          permissions: ['fee.manage', 'staff.manage'],
        ),
        false,
      ),
      'Attendance Staff': (
        _who(
          'attendance_staff',
          campusId: 'c1',
          permissions: ['attendance.mark', 'staff.manage'],
        ),
        false,
      ),
      'permissions unknown → server decides (unchanged behaviour)': (
        _who('admin', known: false),
        true,
      ),
      'no identity supplied → server decides (unchanged behaviour)': (
        null,
        true,
      ),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        final (viewer, offered) = entry.value;
        final server = await _pump(tester, viewer);
        expect(find.byKey(_other), offered ? findsOneWidget : findsNothing);
        expect(
          find.byKey(_nologin),
          findsNothing,
          reason: 'no login, nothing to delegate',
        );
        if (viewer != null && viewer.permissionsKnown) {
          expect(
            find.byKey(_self),
            findsNothing,
            reason:
                'never on the viewer\'s own row (server refuses self-changes)',
          );
        }
        expect(
          find.text('Bushra Teacher'),
          findsOneWidget,
          reason: 'rows are listed regardless',
        );
        _noMutations(server);
      });
    }

    test('helper matches the server rule', () {
      expect(canAdministerCampusRoles(null), isNull);
      expect(canAdministerCampusRoles(_who('admin', known: false)), isNull);
      // A campus-scoped admin role is NOT institution-wide.
      expect(
        canAdministerCampusRoles(
          _who(
            'institution_admin',
            campusId: 'c1',
            permissions: ['user.manage'],
          ),
        ),
        isFalse,
      );
      expect(canAdministerCampusRoles(_who('super_admin')), isTrue);
    });
  });

  for (final width in [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
    testWidgets(
      '${width.toInt()} px: no overflow; table or cards; login status and action present',
      (tester) async {
        final server = await _pump(
          tester,
          _who('institution_owner', permissions: ['user.manage']),
          width: width,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Bushra Teacher', findRichText: true),
          findsWidgets,
        );
        expect(find.text('Has login'), findsWidgets);
        expect(find.text('No login'), findsWidgets);
        expect(find.byKey(_other), findsOneWidget);
        if (width >= AdaptiveDataView.tableBreakpoint) {
          expect(find.text('Actions'), findsOneWidget);
          expect(find.text('Login'), findsOneWidget, reason: 'table header');
        }
        _noMutations(server);
      },
    );
  }

  testWidgets(
    '"Campus roles" opens the sheet (read-only load); rows do not navigate',
    (tester) async {
      final server = await _pump(
        tester,
        _who('institution_owner', permissions: ['user.manage']),
      );
      await tester.tap(find.text('Nadia Nologin'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add a campus role'),
        findsNothing,
        reason: 'row tap does nothing',
      );
      await tester.tap(find.byKey(_other));
      await tester.pumpAndSettle();
      expect(find.text('Add a campus role'), findsOneWidget);
      expect(server.requests, contains('GET /api/users/u-2/campus-grants'));
      _noMutations(server);
    },
  );

  testWidgets(
    'keyboard: group chips and the action are reachable; names are specific',
    (tester) async {
      final handle = tester.ensureSemantics();
      final server = await _pump(
        tester,
        _who('institution_owner', permissions: ['user.manage']),
      );
      expect(
        find.bySemanticsLabel('Campus roles for Bushra Teacher'),
        findsOneWidget,
      );
      bool focused(String label) => tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isFocused
          .toString()
          .contains('isTrue');
      var students = false;
      for (var i = 0; i < 6 && !students; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        students = focused('Students');
      }
      expect(students, isTrue, reason: 'group chip is a tab stop');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Ali Khan', findRichText: true),
        findsWidgets,
        reason: 'Enter switched group',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // back to Staff, then on to the action
      var staff = false;
      for (var i = 0; i < 6 && !staff; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        staff = focused('Staff');
      }
      if (!staff) {
        for (var i = 0; i < 6 && !staff; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          staff = focused('Staff');
        }
      }
      expect(staff, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      var action = false;
      for (var i = 0; i < 12 && !action; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        action = focused('Campus roles for Bushra Teacher');
      }
      expect(action, isTrue, reason: 'row action is a tab stop');
      _noMutations(server);
      handle.dispose();
    },
  );

  testWidgets(
    'group chips keep their natural width (they had stretched to the page width)',
    (tester) async {
      await _pump(
        tester,
        _who('institution_owner', permissions: ['user.manage']),
      );
      final staff = tester.getRect(find.byKey(const Key('people-group-staff')));
      final students = tester.getRect(
        find.byKey(const Key('people-group-students')),
      );
      expect(staff.width, lessThan(300));
      expect(students.top, staff.top, reason: 'chips sit on one row');
      expect(students.left, greaterThan(staff.right));
    },
  );

  testWidgets(
    'Campus roles sheet takes focus on open; Escape closes it; no mutation',
    (tester) async {
      final server = await _pump(
        tester,
        _who('institution_owner', permissions: ['user.manage']),
      );
      await tester.tap(find.byKey(_other));
      await tester.pumpAndSettle();
      expect(find.text('Add a campus role'), findsOneWidget);
      final sheetCtx = tester.element(find.text('Add a campus role'));
      final focusCtx = FocusManager.instance.primaryFocus?.context;
      var inSheet = false;
      sheetCtx.visitAncestorElements((e) {
        inSheet = inSheet || identical(e, focusCtx);
        return !inSheet;
      });
      expect(inSheet, isTrue, reason: 'focus moved into the sheet');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Add a campus role'), findsNothing);
      _noMutations(server);
    },
  );

  group('Campus roles sheet follows the viewer policy and the target', () {
    List<String?> roleOptions(WidgetTester tester) => [
      for (final item
          in tester
              .widget<DropdownButton<String>>(
                find.byKey(const Key('campus-role-role')),
              )
              .items!)
        item.value,
    ];

    testWidgets('institution owner: every ordinary role is offered', (
      tester,
    ) async {
      await _pump(
        tester,
        _who('institution_owner', permissions: ['user.manage']),
      );
      await tester.tap(find.byKey(_other));
      await tester.pumpAndSettle();
      expect(
        roleOptions(tester),
        containsAll(['teacher', 'attendance_staff', 'finance_staff', 'staff']),
      );
    });

    testWidgets(
      'campus admin with user.manage: only teacher and attendance staff (ADR-011)',
      (tester) async {
        await _pump(
          tester,
          _who(
            'campus_admin',
            campusId: 'c1',
            permissions: ['user.manage', 'staff.manage'],
          ),
        );
        await tester.tap(find.byKey(_other));
        await tester.pumpAndSettle();
        expect(roleOptions(tester), ['teacher', 'attendance_staff']);
      },
    );

    testWidgets(
      'privileged target (server lists a campus_admin grant): no changes offered',
      (tester) async {
        final server = await _pump(
          tester,
          _who('institution_owner', permissions: ['user.manage']),
        );
        server.grantsByUser['u-2'] = [
          {
            'grantId': 'g1',
            'campusId': 'c1',
            'campusName': 'North',
            'role': 'campus_admin',
          },
        ];
        await tester.tap(find.byKey(_other));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('campus-roles-protected')), findsOneWidget);
        expect(find.byKey(const Key('campus-role-add')), findsNothing);
        expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
        _noMutations(server);
      },
    );

    testWidgets(
      'ordinary target: changes stay available (not hidden by title)',
      (tester) async {
        final server = await _pump(
          tester,
          _who('institution_owner', permissions: ['user.manage']),
        );
        server.grantsByUser['u-2'] = [
          {
            'grantId': 'g1',
            'campusId': 'c1',
            'campusName': 'North',
            'role': 'teacher',
          },
        ];
        await tester.tap(find.byKey(_other));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('campus-roles-protected')), findsNothing);
        expect(find.byKey(const Key('campus-role-add')), findsOneWidget);
        expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
        _noMutations(server);
      },
    );

    testWidgets(
      'Escape returns focus to the "Campus roles" button; its label never turns into "…"',
      (tester) async {
        final server = await _pump(
          tester,
          _who('institution_owner', permissions: ['user.manage']),
        );
        bool focusInOpener() {
          final ctx = FocusManager.instance.primaryFocus?.context;
          if (ctx == null) return false;
          final target = tester.element(find.byKey(_other));
          var hit = identical(ctx, target);
          ctx.visitAncestorElements((e) {
            hit = hit || identical(e, target);
            return !hit;
          });
          return hit;
        }

        for (var i = 0; i < 12 && !focusInOpener(); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusInOpener(), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('Add a campus role'), findsOneWidget);
        expect(find.text('Campus roles…'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(focusInOpener(), isTrue, reason: 'restored to the opener');
        _noMutations(server);
      },
    );
  });

  testWidgets('search still filters client-side', (tester) async {
    await _pump(
      tester,
      _who('institution_owner', permissions: ['user.manage']),
    );
    await tester.enterText(find.byType(TextField), 'nadia');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Nadia Nologin', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Bushra Teacher', findRichText: true),
      findsNothing,
    );
  });
}

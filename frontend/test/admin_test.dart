import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/shell/role_destinations.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/states/screen_state.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/admin/data/import_repository.dart';
import 'package:smartems/features/admin/data/user_wizard_repository.dart';
import 'package:smartems/features/admin/domain/admin_models.dart';
import 'package:smartems/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:smartems/features/admin/presentation/csv_import_screen.dart';
import 'package:smartems/features/admin/presentation/students_list_screen.dart';

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

Dio _dio(_Adapter a) =>
    Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = a;

SectionCompleteness _section(
  String name, {
  int students = 0,
  bool timetable = false,
  bool teacher = false,
}) =>
    SectionCompleteness(
      sectionId: name,
      sectionName: name,
      className: 'Class 9',
      studentCount: students,
      hasTimetable: timetable,
      hasClassTeacher: teacher,
    );

class _FakeAdmin extends AdminRepository {
  _FakeAdmin({this.dashboard, this.students = const [], this.fail = false})
      : super(Dio());

  final AdminDashboard? dashboard;
  final List<AdminStudent> students;
  final bool fail;

  @override
  Future<AdminDashboard> loadDashboard() async {
    if (fail) throw const LoadFailure(message: 'boom');
    return dashboard!;
  }

  @override
  Future<List<AdminStudent>> loadStudentsWithPlacement() async {
    if (fail) throw const LoadFailure(message: 'boom');
    return students;
  }
}

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
  group('D-15 completeness sort', () {
    test('least complete first, label as tie-break', () {
      final sorted = sortByCompleteness([
        _section('D', students: 5, timetable: true, teacher: true),
        _section('C', students: 5, timetable: true),
        _section('B', students: 5),
        _section('A2'),
        _section('A1'),
      ]);
      expect(sorted.map((s) => s.sectionId), ['A1', 'A2', 'B', 'C', 'D']);
    });

    test('a complete section invents no next action (D-19)', () {
      expect(
        _section('X', students: 1, timetable: true, teacher: true).nextAction,
        isNull,
      );
    });
  });

  group('D-14 — asserted both ways', () {
    test('no records → brand-new school', () {
      const d = AdminDashboard(studentCount: 0, staffCount: 0, sections: []);
      expect(d.isBrandNewSchool, isTrue);
    });

    test('records exist but counters read zero → NOT brand-new', () {
      // A section with no students: every counter a user sees is zero, and
      // yet the school has been set up. The checklist must not appear.
      final d = AdminDashboard(
        studentCount: 0,
        staffCount: 0,
        sections: [_section('A')],
      );
      expect(d.isBrandNewSchool, isFalse);
    });

    testWidgets('checklist renders only for the empty school',
        (tester) async {
      await tester.pumpWidget(_host(AdminDashboardScreen(
        repository: _FakeAdmin(
          dashboard:
              const AdminDashboard(studentCount: 0, staffCount: 0, sections: []),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Set up your school'), findsOneWidget);

      await tester.pumpWidget(_host(AdminDashboardScreen(
        key: const ValueKey('b'),
        repository: _FakeAdmin(
          dashboard: AdminDashboard(
            studentCount: 0,
            staffCount: 0,
            sections: [_section('A')],
          ),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Set up your school'), findsNothing);
      expect(find.text('No students enrolled'), findsOneWidget);
    });

    testWidgets('a failed load is an error, never the empty-school checklist',
        (tester) async {
      await tester
          .pumpWidget(_host(AdminDashboardScreen(repository: _FakeAdmin(fail: true))));
      await tester.pumpAndSettle();
      expect(find.text('Set up your school'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('D-17 wizard recovery', () {
    WizardDraft draft() => WizardDraft(
          role: WizardRole.teacher,
          username: 'new.teacher',
          password: 'Secret123!',
          firstName: 'Sara',
          lastName: 'Ali',
          campusId: 'c-1',
          employeeCode: 'T-9',
        );

    test('failure after user creation keeps the userId', () async {
      final a = _Adapter((o) => o.path == ApiConfig.provisionPath
          ? _json(201, {'userId': 'u-1'})
          : _json(500, {'message': 'link failed'}));
      final out = await UserWizardRepository(_dio(a)).commit(draft());

      expect(out, isA<WizardPartiallyFailed>());
      expect((out as WizardPartiallyFailed).userId, 'u-1');
    });

    test('resume reuses the userId and never provisions a second user',
        () async {
      final a = _Adapter((o) => _json(201, {'id': 'st-1'}));
      final out = await UserWizardRepository(_dio(a))
          .commit(draft(), existingUserId: 'u-1');

      expect(out, isA<WizardSucceeded>());
      expect(a.requests.where((r) => r.path == ApiConfig.provisionPath),
          isEmpty);
      expect((a.requests.single.data as Map)['userId'], 'u-1');
    });

    test('provision failure writes nothing and is a clean failure', () async {
      final a = _Adapter((o) => _json(409, {'message': 'taken'}));
      final out = await UserWizardRepository(_dio(a)).commit(draft());

      expect(out, isA<WizardFailed>());
      expect(a.requests, hasLength(1));
    });
  });

  group('Students list', () {
    final roster = [
      const AdminStudent(
          id: '1', fullName: 'Bilal Ahmed', admissionNumber: 'ADM-1'),
      const AdminStudent(
          id: '2', fullName: 'Sana Khan', admissionNumber: 'ADM-2'),
    ];

    testWidgets('client-side filter (B-02) and its own empty state',
        (tester) async {
      await tester.pumpWidget(
          _host(StudentsListScreen(repository: _FakeAdmin(students: roster))));
      await tester.pumpAndSettle();
      expect(find.text('Bilal Ahmed'), findsOneWidget);
      expect(find.text('Not enrolled'), findsNWidgets(2));

      await tester.enterText(find.byType(TextField), 'sana');
      await tester.pumpAndSettle();
      expect(find.text('Bilal Ahmed'), findsNothing);
      expect(find.text('Sana Khan'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      // Filtered-to-nothing is not "no students yet".
      expect(find.text('No students yet'), findsNothing);
    });

    testWidgets('empty roster shows the empty state', (tester) async {
      await tester.pumpWidget(
          _host(StudentsListScreen(repository: _FakeAdmin())));
      await tester.pumpAndSettle();
      expect(find.text('No students yet'), findsOneWidget);
    });
  });

  group('CSV import', () {
    testWidgets('shows snake_case header up front and per-row errors',
        (tester) async {
      final a = _Adapter((o) => o.path == ApiConfig.importStudentsPath
          ? _json(200, {
              'jobId': 'j-1',
              'status': 'COMPLETED',
              'totalRows': 2,
              'successRows': 1,
              'errorRows': 1,
            })
          : _json(200, {
              'content': [
                {'rowNumber': 3, 'message': 'first_name missing'},
              ],
            }));
      await tester.pumpWidget(
          _host(CsvImportScreen(repository: ImportRepository(_dio(a)))));
      expect(find.text('first_name,last_name,admission_number'),
          findsOneWidget);

      await tester.enterText(find.byType(TextField),
          'first_name,last_name,admission_number\nA,B,1\n,C,2');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 of 2 rows imported'), findsOneWidget);
      // The rejected rows sit below the fold of the default test viewport,
      // and ListView only builds what is on screen.
      await tester.scrollUntilVisible(
        find.text('Row 3'),
        200,
        // The paste box is a Scrollable too; aim at the page's list.
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Row 3'), findsOneWidget);
      expect(find.text('first_name missing'), findsOneWidget);
      // Sent as multipart — JSON returns a 500 on this endpoint.
      expect(a.requests.first.data, isA<FormData>());
    });
  });

  group('Campus lookup', () {
    test('accepts a bare JSON array (what broke Add user live)', () async {
      final a = _Adapter((o) => _json(200, [
            {'id': 'c-1', 'name': 'Main'},
          ]));
      expect(await AdminRepository(_dio(a)).loadCampusIds(), ['c-1']);
    });

    test('accepts a Spring page envelope too', () async {
      final a = _Adapter((o) => _json(200, {
            'content': [
              {'id': 'c-1'},
            ],
          }));
      expect(await AdminRepository(_dio(a)).loadCampusIds(), ['c-1']);
    });
  });

  group('Routing', () {
    test('admin shell mirrors forRoles precedence', () {
      expect(RoleDestinations.isAdminShell(['admin']), isTrue);
      expect(RoleDestinations.isAdminShell(['admin', 'teacher']), isFalse);
      expect(RoleDestinations.isAdminShell(['parent']), isFalse);
    });
  });

  group('Layout', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('dashboard has no overflow at $width, 2× text, RTL',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(
          AdminDashboardScreen(
            repository: _FakeAdmin(
              dashboard: AdminDashboard(
                studentCount: 120,
                staffCount: 9,
                sections: [
                  _section('A long section name', students: 40),
                  _section('B'),
                ],
              ),
            ),
          ),
          textScale: 2,
          dir: TextDirection.rtl,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Polish pass: the section list holds EVERY section, sorted least
  // complete first — it is not filtered to the unfinished ones. So the
  // heading has to follow the data or it states something untrue.
  group('dashboard heading follows the data', () {
    testWidgets('it counts what is unfinished when something is',
        (tester) async {
      await tester.pumpWidget(_host(AdminDashboardScreen(
        repository: _FakeAdmin(
          dashboard: AdminDashboard(
            studentCount: 10,
            staffCount: 3,
            sections: [
              _section('A', students: 5, timetable: true, teacher: true),
              _section('B', students: 5),
              _section('C'),
            ],
          ),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Sections needing attention'), findsOneWidget);
      expect(
        find.text('2 of 3 sections are unfinished. Least complete first.'),
        findsOneWidget,
      );
    });

    testWidgets('it does not claim attention is needed when none is',
        (tester) async {
      await tester.pumpWidget(_host(AdminDashboardScreen(
        repository: _FakeAdmin(
          dashboard: AdminDashboard(
            studentCount: 10,
            staffCount: 3,
            sections: [
              _section('A', students: 5, timetable: true, teacher: true),
              _section('B', students: 5, timetable: true, teacher: true),
            ],
          ),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Sections needing attention'), findsNothing);
      expect(find.text('Sections'), findsOneWidget);
      expect(find.text('Every section is set up.'), findsOneWidget);
    });

    testWidgets('the landing screen carries a subtitle, like the hubs do',
        (tester) async {
      await tester.pumpWidget(_host(AdminDashboardScreen(
        repository: _FakeAdmin(
          dashboard: AdminDashboard(
            studentCount: 10,
            staffCount: 3,
            sections: [_section('A', students: 5)],
          ),
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Where the school needs attention.'), findsOneWidget);
    });

    testWidgets('the KPI row stacks on a narrow viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: MediaQuery(
          // Three equal columns crammed here before — "Students" wrapped
          // while "Staff" did not, and the row went ragged.
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: AdminDashboardScreen(
            repository: _FakeAdmin(
              dashboard: AdminDashboard(
                studentCount: 400,
                staffCount: 30,
                sections: [_section('A', students: 5)],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Sections'), findsWidgets);
    });
  });
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';
import 'package:smartems/features/setup/domain/setup_models.dart';
import 'package:smartems/features/setup/presentation/academic_years_screen.dart';
import 'package:smartems/features/setup/presentation/classes_screen.dart';
import 'package:smartems/features/setup/presentation/sections_screen.dart';
import 'package:smartems/features/setup/presentation/setup_home_screen.dart';
import 'package:smartems/features/setup/presentation/subjects_screen.dart';
import 'package:smartems/features/setup/presentation/teaching_assignments_screen.dart';
import 'package:smartems/features/setup/presentation/timetable_builder_screen.dart';

/// A stub of the setup endpoints with this backend's REAL quirks:
/// `current` ignored on write, `?classId=` ignored, clash and validation
/// both answering 409.
class _SetupServer implements HttpClientAdapter {
  _SetupServer();

  final List<RequestOptions> requests = [];
  final List<Map<String, dynamic>> years = [];
  final List<Map<String, dynamic>> classes = [];
  final List<Map<String, dynamic>> sections = [];
  final List<Map<String, dynamic>> subjects = [];
  final List<Map<String, dynamic>> assignments = [];
  final List<Map<String, dynamic>> periods = [];
  final List<Map<String, dynamic>> slots = [];

  /// The message the next slot POST fails with, if any.
  String? slotFailure;
  bool assignmentConflict = false;
  int _id = 0;

  String _next(String prefix) => '$prefix-${_id++}';

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;
    final body = o.data is Map ? (o.data as Map).cast<String, dynamic>() : null;

    if (o.method == 'GET') {
      return switch (path) {
        '/api/academic-years' => _page(years),
        '/api/classes' => _page(classes),
        // The real backend ignores ?classId= — the stub does too, so a test
        // cannot accidentally depend on a filter that does not exist.
        '/api/sections' => _page(sections),
        '/api/subjects' => _page(subjects),
        '/api/campuses' => _json(200, [
            {'id': 'campus-1', 'name': 'Main'},
          ]),
        '/api/staff' => _page([
            {
              'id': 'staff-1',
              'firstName': 'Ayesha',
              'lastName': 'Khan',
              'userId': 'u-1',
            },
          ]),
        '/api/students' => _page(const []),
        '/api/timetable/periods' => _json(200, periods),
        '/api/timetable/rooms' => _json(200, const []),
        _ when path.startsWith('/api/teaching-assignments/section/') =>
          _page(assignments),
        _ when path.startsWith('/api/timetable/section/') => _json(200, slots),
        _ when path.startsWith('/api/guardians/student/') =>
          _json(200, const []),
        _ => _json(404, {'message': 'no route'}),
      };
    }

    if (o.method == 'POST') {
      switch (path) {
        case '/api/academic-years':
          // Mirrors the live behaviour: `current` is never honoured.
          final row = {
            'id': _next('year'),
            'name': body?['name'],
            'startDate': body?['startDate'],
            'endDate': body?['endDate'],
            'current': false,
          };
          years.add(row);
          return _json(201, row);
        case '/api/classes':
          final row = {
            'id': _next('class'),
            'name': body?['name'],
            'levelOrder': body?['levelOrder'],
          };
          classes.add(row);
          return _json(201, row);
        case '/api/sections':
          final row = {
            'id': _next('section'),
            'classId': body?['classId'],
            'academicYearId': body?['academicYearId'],
            'name': body?['name'],
            'capacity': body?['capacity'],
            'classTeacherId': body?['classTeacherId'],
          };
          sections.add(row);
          return _json(201, row);
        case '/api/subjects':
          final row = {
            'id': _next('subject'),
            'name': body?['name'],
            'code': body?['code'],
          };
          subjects.add(row);
          return _json(201, row);
        case '/api/teaching-assignments':
          if (assignmentConflict) {
            return _json(409, {'message': 'Conflicts with existing data'});
          }
          final row = {
            'id': _next('ta'),
            'staffId': body?['staffId'],
            'sectionId': body?['sectionId'],
            'subjectId': body?['subjectId'],
            'academicYearId': body?['academicYearId'],
          };
          assignments.add(row);
          return _json(201, row);
        case '/api/timetable/periods':
          final row = {
            'id': _next('period'),
            'name': body?['name'],
            'startTime': body?['startTime'],
            'endTime': body?['endTime'],
            'sortOrder': body?['sortOrder'],
            'isBreak': body?['isBreak'] ?? false,
          };
          periods.add(row);
          return _json(201, row);
        case '/api/timetable/slots':
          if (slotFailure != null) {
            return _json(409, {'message': slotFailure});
          }
          final row = {
            'id': _next('slot'),
            'sectionId': body?['sectionId'],
            'dayOfWeek': body?['dayOfWeek'],
            'periodId': body?['periodId'],
            'subjectId': body?['subjectId'],
            'teacherStaffId': body?['teacherStaffId'],
            'roomId': body?['roomId'],
          };
          slots.add(row);
          return _json(201, row);
      }
    }
    return _json(404, {'message': 'no route'});
  }

  ResponseBody _page(List<Map<String, dynamic>> rows) =>
      _json(200, {'content': rows, 'totalElements': rows.length});

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

Dio _dio(_SetupServer s) =>
    Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = s;

Widget _host(Widget child, {Size? size, double textScale = 1}) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: MediaQuery(
        data: MediaQueryData(
          size: size ?? const Size(1000, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    );

const _year = AcademicYear(
  id: 'year-1',
  name: '2026-27',
  startDate: '2026-08-01',
  endDate: '2027-05-31',
  current: true,
);

void main() {
  group('Class order (levelOrder, not alphabetical)', () {
    test('Class 2 comes before Class 10', () {
      final sorted = sortClasses(const [
        SchoolClass(id: 'a', name: 'Class 10', levelOrder: 10),
        SchoolClass(id: 'b', name: 'Class 2', levelOrder: 2),
      ]);
      expect(sorted.map((c) => c.name), ['Class 2', 'Class 10']);
    });

    test('classes without an order sort after the ones that have it', () {
      final sorted = sortClasses(const [
        SchoolClass(id: 'a', name: 'Nursery'),
        SchoolClass(id: 'b', name: 'Class 1', levelOrder: 1),
      ]);
      expect(sorted.first.name, 'Class 1');
    });
  });

  group('Slot failures — 409 does not mean clash', () {
    test('the two known clash wordings are recognised', () {
      expect(
        SlotFailure.fromMessage('Teacher is already scheduled at that '
                'day/period')
            .kind,
        SlotFailureKind.teacherClash,
      );
      expect(
        SlotFailure.fromMessage('Room is already booked at that day/period')
            .kind,
        SlotFailureKind.roomClash,
      );
    });

    test('anything else is passed through verbatim, NOT as a clash', () {
      // The live backend answers 409 for bad input too. Rendering that as a
      // clash would send the admin hunting for a conflict that does not
      // exist.
      final f = SlotFailure.fromMessage('Conflicts with existing data');
      expect(f.kind, SlotFailureKind.other);
      expect(f.message, 'Conflicts with existing data');
    });
  });

  group('Academic years', () {
    testWidgets('no set-current control — an explanation instead',
        (tester) async {
      final s = _SetupServer()
        ..years.add({
          'id': 'y1',
          'name': '2025-26',
          'startDate': '2025-08-01',
          'endDate': '2026-05-31',
          'current': true,
        });
      await tester.pumpWidget(_host(AcademicYearsScreen(
        repository: SetupRepository(_dio(s)),
        campusId: 'campus-1',
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be changed in the app yet'),
          findsOneWidget);
      expect(find.text('Set as current'), findsNothing);
      expect(find.text('Make current'), findsNothing);
      expect(find.text('Current'), findsOneWidget);
    });

    testWidgets('a malformed date is caught before anything is sent',
        (tester) async {
      final s = _SetupServer();
      await tester.pumpWidget(_host(AcademicYearsScreen(
        repository: SetupRepository(_dio(s)),
        campusId: 'campus-1',
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add an academic year'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '2026-27');
      await tester.enterText(find.byType(TextField).at(1), '1 Aug 2026');
      await tester.pumpAndSettle();

      expect(find.textContaining('YYYY-MM-DD'), findsWidgets);
      expect(s.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test('create does not send `current` — the API ignores it anyway',
        () async {
      final s = _SetupServer();
      await SetupRepository(_dio(s)).createYear(
        campusId: 'campus-1',
        name: '2026-27',
        startDate: '2026-08-01',
        endDate: '2027-05-31',
      );
      final body = s.requests.last.data as Map;
      expect(body.containsKey('current'), isFalse);
    });
  });

  group('Sections', () {
    testWidgets('states the year it writes into', (tester) async {
      final s = _SetupServer();
      await tester.pumpWidget(_host(SectionsScreen(
        repository: SetupRepository(_dio(s)),
        admin: AdminRepository(_dio(s)),
        classes: const [SchoolClass(id: 'c1', name: 'Class 9', levelOrder: 9)],
        year: _year,
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('belong to 2026-27'), findsOneWidget);
    });

    testWidgets('sections of another year are not shown as this year’s',
        (tester) async {
      final s = _SetupServer()
        ..sections.add({
          'id': 's-old',
          'classId': 'c1',
          'academicYearId': 'OTHER',
          'name': 'Old-A',
        });
      await tester.pumpWidget(_host(SectionsScreen(
        repository: SetupRepository(_dio(s)),
        admin: AdminRepository(_dio(s)),
        classes: const [SchoolClass(id: 'c1', name: 'Class 9')],
        year: _year,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Old-A'), findsNothing);
      expect(find.textContaining('exist in other years'), findsOneWidget);
    });
  });

  group('Teaching assignments — add-only, said up front', () {
    Widget screen(_SetupServer s) => _host(TeachingAssignmentsScreen(
          repository: SetupRepository(_dio(s)),
          admin: AdminRepository(_dio(s)),
          classes: const [SchoolClass(id: 'c1', name: 'Class 9')],
          sections: const [
            Section(
              id: 'sec-1',
              classId: 'c1',
              academicYearId: 'year-1',
              name: '9-C',
            ),
          ],
          subjects: const [Subject(id: 'sub-1', name: 'Mathematics')],
          year: _year,
        ));

    testWidgets('warns before the action, and offers no edit or delete',
        (tester) async {
      final s = _SetupServer()
        ..assignments.add({
          'id': 'ta-1',
          'staffId': 'staff-1',
          'sectionId': 'sec-1',
          'subjectId': 'sub-1',
          'academicYearId': 'year-1',
        });
      await tester.pumpWidget(screen(s));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be changed or removed yet'),
          findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      // The existing row shows names, joined client-side from ids.
      expect(find.text('Mathematics'), findsWidgets);
      expect(find.text('Ayesha Khan'), findsWidgets);
    });

    testWidgets('a duplicate is explained in the admin’s words',
        (tester) async {
      final s = _SetupServer()..assignmentConflict = true;
      await tester.pumpWidget(screen(s));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assign a teacher'));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be changed or removed afterwards'),
          findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Mathematics').last);
      await tester.tap(find.bySemanticsLabel('Ayesha Khan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already has a teacher'), findsOneWidget);
      expect(find.textContaining('Conflicts with existing data'), findsNothing);
    });
  });

  group('Timetable', () {
    _SetupServer serverWithPeriods() => _SetupServer()
      ..periods.addAll([
        {
          'id': 'p1',
          'name': 'Period 1',
          'startTime': '08:00:00',
          'endTime': '08:45:00',
          'sortOrder': 1,
          'isBreak': false,
        },
        {
          'id': 'p2',
          'name': 'Break',
          'startTime': '08:45:00',
          'endTime': '09:00:00',
          'sortOrder': 2,
          'isBreak': true,
        },
      ]);

    Widget screen(_SetupServer s) => TimetableBuilderScreen(
          repository: SetupRepository(_dio(s)),
          admin: AdminRepository(_dio(s)),
          campusId: 'campus-1',
          classes: const [SchoolClass(id: 'c1', name: 'Class 9')],
          sections: const [
            Section(
              id: 'sec-1',
              classId: 'c1',
              academicYearId: 'year-1',
              name: '9-C',
            ),
          ],
          subjects: const [Subject(id: 'sub-1', name: 'Mathematics')],
          year: _year,
        );

    testWidgets('wide: a grid with every weekday', (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(screen(serverWithPeriods()),
          size: const Size(1366, 900)));
      await tester.pumpAndSettle();

      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      // The break is a band, not six tappable cells.
      expect(find.textContaining('Break · 08:45–09:00'), findsOneWidget);
    });

    testWidgets('narrow: a day picker and a list, no grid', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          _host(screen(serverWithPeriods()), size: const Size(360, 900)));
      await tester.pumpAndSettle();

      // Day chips exist; the grid header row does not.
      expect(find.bySemanticsLabel('Mon'), findsOneWidget);
      expect(find.text('Day'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a clash lands on the cell, and admits what it cannot show',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final s = serverWithPeriods()
        ..slotFailure = 'Teacher is already scheduled at that day/period';
      await tester.pumpWidget(
          _host(screen(s), size: const Size(1366, 900)));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Mon Period 1, empty'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Mathematics').last);
      await tester.tap(find.bySemanticsLabel('Ayesha Khan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to timetable'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already teaches at this time'),
          findsOneWidget);
      expect(find.textContaining('cannot yet show which class'),
          findsOneWidget);
    });

    testWidgets('a validation 409 is shown verbatim, not as a clash',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final s = serverWithPeriods()
        ..slotFailure = 'Conflicts with existing data';
      await tester.pumpWidget(
          _host(screen(s), size: const Size(1366, 900)));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Mon Period 1, empty'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Mathematics').last);
      await tester.tap(find.bySemanticsLabel('Ayesha Khan').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to timetable'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already teaches'), findsNothing);
      expect(find.textContaining('Conflicts with existing data'),
          findsOneWidget);
    });
  });

  group('Setup hub — dependencies explained, not failed', () {
    testWidgets('a blocked step says what is missing', (tester) async {
      final s = _SetupServer(); // nothing exists yet
      await tester.pumpWidget(_host(SetupHomeScreen(
        setup: SetupRepository(_dio(s)),
        admin: AdminRepository(_dio(s)),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Create an academic year first'), findsWidgets);
      expect(find.text('Could not load this'), findsNothing);
      // Step 3 is inert while it is blocked.
      expect(find.bySemanticsLabel('Sections'), findsNothing);
    });

    testWidgets('steps open once their dependency exists', (tester) async {
      final s = _SetupServer()
        ..years.add({
          'id': 'y1',
          'name': '2026-27',
          'startDate': '2026-08-01',
          'endDate': '2027-05-31',
          'current': true,
        })
        ..classes.add({'id': 'c1', 'name': 'Class 9', 'levelOrder': 9});
      await tester.pumpWidget(_host(SetupHomeScreen(
        setup: SetupRepository(_dio(s)),
        admin: AdminRepository(_dio(s)),
      )));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Sections'), findsOneWidget);
      expect(find.textContaining('Working year: 2026-27'), findsOneWidget);
    });

    testWidgets('warns when no year is flagged current', (tester) async {
      final s = _SetupServer()
        ..years.add({
          'id': 'y1',
          'name': '2026-27',
          'startDate': '2026-08-01',
          'endDate': '2027-05-31',
          'current': false,
        });
      await tester.pumpWidget(_host(SetupHomeScreen(
        setup: SetupRepository(_dio(s)),
        admin: AdminRepository(_dio(s)),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('No year is marked as current'),
          findsOneWidget);
    });
  });

  group('Layout', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('setup screens: no overflow at $width, 2× text',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final s = _SetupServer()
          ..years.add({
            'id': 'y1',
            'name': '2026-27',
            'startDate': '2026-08-01',
            'endDate': '2027-05-31',
            'current': true,
          })
          ..classes.add({'id': 'c1', 'name': 'Class 9', 'levelOrder': 9})
          ..subjects.add({'id': 'sub-1', 'name': 'Mathematics', 'code': 'M'});

        for (final screen in [
          SetupHomeScreen(
            setup: SetupRepository(_dio(s)),
            admin: AdminRepository(_dio(s)),
          ),
          ClassesScreen(
            repository: SetupRepository(_dio(s)),
            campusId: 'campus-1',
          ),
          SubjectsScreen(repository: SetupRepository(_dio(s))),
        ]) {
          await tester.pumpWidget(
            _host(screen, size: Size(width, 900), textScale: 2),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}

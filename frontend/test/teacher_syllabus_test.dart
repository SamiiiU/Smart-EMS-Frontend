import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academics/data/academics_repository.dart';
import 'package:smartems/features/academics/data/teacher_syllabus_context.dart';
import 'package:smartems/features/academics/presentation/syllabus_screen.dart';
import 'package:smartems/features/academics/presentation/teacher_syllabus_flow.dart';

/// Teacher Syllabus route (owner decision 18 Oct 2026): only the teacher's own
/// active assignments are offered; nothing institution-wide.
class _Server implements HttpClientAdapter {
  _Server({this.mySections, this.fail = false});
  final List<Map<String, Object?>>? mySections;
  final bool fail;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    paths.add(o.uri.path);
    ResponseBody json(int code, Object body) =>
        ResponseBody.fromString(jsonEncode(body), code, headers: {'content-type': ['application/json']});
    final p = o.uri.path;
    if (fail) return json(500, {'message': 'Server unavailable'});
    if (p == '/api/attendance/my-sections') return json(200, mySections ?? []);
    if (p == '/api/teaching-assignments/section/sec-1') {
      return json(200, {'content': [
        {'id': 'ta-1', 'staffId': 'me', 'sectionId': 'sec-1', 'subjectId': 'math', 'academicYearId': 'y1', 'status': 'active'},
        {'id': 'ta-2', 'staffId': 'someone-else', 'sectionId': 'sec-1', 'subjectId': 'english', 'academicYearId': 'y1', 'status': 'active'},
        {'id': 'ta-3', 'staffId': 'me', 'sectionId': 'sec-1', 'subjectId': 'science', 'academicYearId': 'y1', 'status': 'ended'},
      ]});
    }
    if (p == '/api/teaching-assignments/section/sec-2') {
      return json(200, {'content': [
        {'id': 'ta-4', 'staffId': 'someone-else', 'sectionId': 'sec-2', 'subjectId': 'math', 'academicYearId': 'y1', 'status': 'active'},
      ]});
    }
    if (p == '/api/sections/sec-1') return json(200, {'id': 'sec-1', 'classId': 'c5', 'academicYearId': 'y1', 'name': '5-A'});
    if (p == '/api/subjects') {
      return json(200, {'content': [
        {'id': 'math', 'name': 'Mathematics'}, {'id': 'english', 'name': 'English'}, {'id': 'science', 'name': 'Science'},
      ], 'last': true, 'number': 0, 'totalPages': 1});
    }
    if (p == '/api/academic-years/y1') {
      return json(200, {'id': 'y1', 'name': '2025-26', 'startDate': '2025-04-01', 'endDate': '2026-03-31', 'current': true});
    }
    if (p == '/api/syllabus/chapters' || p == '/api/syllabus/progress') return json(200, p.endsWith('chapters') ? [] : {});
    return json(404, {'message': 'not found'});
  }

  @override
  void close({bool force = false}) {}
}

AcademicsRepository _repo(_Server s) => AcademicsRepository(Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))..httpClientAdapter = s);

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light(role: AppRole.teacher), home: Scaffold(body: child));

const _twoSections = [
  {'sectionId': 'sec-1', 'sectionName': '5-A', 'className': 'Grade 5', 'campusId': 'main', 'academicYearId': 'y1'},
  {'sectionId': 'sec-2', 'sectionName': '5-B', 'className': 'Grade 5', 'campusId': 'main', 'academicYearId': 'y1'},
];

void main() {
  test('context offers only this teacher\'s ACTIVE assignments (not colleagues\', not ended)', () async {
    final ctx = await _repo(_Server(mySections: _twoSections)).teacherSyllabusContext('me');
    expect(ctx, isNotNull);
    expect(ctx!.subjects.map((s) => s.name), ['Mathematics']);
    expect(ctx.sections.map((s) => s.id), ['sec-1'], reason: 'sec-2 is taught by someone else');
    expect(ctx.classes.single.id, 'c5');
    expect(ctx.year.name, '2025-26');
  });

  testWidgets('a teacher with assignments sees Syllabus for their subject', (tester) async {
    await tester.pumpWidget(_host(TeacherSyllabusFlow(repository: _repo(_Server(mySections: _twoSections)), staffId: 'me')));
    await tester.pumpAndSettle();
    expect(find.byType(SyllabusScreen), findsOneWidget);
    expect(find.text('Mathematics'), findsWidgets);
    expect(find.text('English'), findsNothing);
  });

  testWidgets('no assignments: a clear empty state, no syllabus calls', (tester) async {
    final server = _Server(mySections: const []);
    await tester.pumpWidget(_host(TeacherSyllabusFlow(repository: _repo(server), staffId: 'me')));
    await tester.pumpAndSettle();
    expect(find.text('No subjects assigned to you'), findsOneWidget);
    expect(server.paths.where((p) => p.startsWith('/api/syllabus')), isEmpty);
  });

  testWidgets('a failed load shows the error with Try again', (tester) async {
    await tester.pumpWidget(_host(TeacherSyllabusFlow(repository: _repo(_Server(fail: true)), staffId: 'me')));
    await tester.pumpAndSettle();
    expect(find.text('Server unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

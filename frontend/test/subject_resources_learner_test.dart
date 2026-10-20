import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academics/data/subject_resources_repository.dart';
import 'package:smartems/features/academics/presentation/learner_resources_screen.dart';

/// D-21 learner view: a stub of GET /api/students/{id}/subject-resources.
class _LearnerServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int status = 200;
  String body = '{"enrollment":null,"resources":[]}';

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromBytes(utf8.encode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _fileId = '0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b';

const _twoSubjects = '''
{"enrollment":{"classId":"c1","className":"Class 8","academicYearId":"y1","academicYearName":"2026"},
 "resources":[
  {"id":"r1","title":"Algebra notes","kind":"file","status":"active","subjectName":"Mathematics",
   "filename":"algebra.pdf","contentType":"application/pdf","sizeBytes":2048,
   "contentPath":"/api/files/$_fileId/content","canDelete":false},
  {"id":"r2","title":"Reading list","kind":"link","status":"active","subjectName":"English",
   "url":"https://example.org/reading","canDelete":false}
 ]}
''';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.student),
      home: child,
    );

({_LearnerServer server, SubjectResourcesRepository repo}) _wire() {
  final server = _LearnerServer();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return (server: server, repo: SubjectResourcesRepository(dio));
}

void main() {
  testWidgets('lists the learner class resources grouped by subject, read-only',
      (tester) async {
    final w = _wire()..server.body = _twoSubjects;
    await tester.pumpWidget(_host(LearnerResourcesScreen(
      repository: w.repo,
      studentId: 'stu-1',
      title: 'Resources',
    )));
    await tester.pumpAndSettle();

    expect(w.server.requests.single.uri.path,
        '/api/students/stu-1/subject-resources');
    expect(w.server.requests.single.method, 'GET');
    expect(find.text('Class 8 · 2026'), findsOneWidget);
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Algebra notes'), findsOneWidget);
    expect(find.text('Reading list'), findsOneWidget);
    // A file offers Download, a link offers Copy link; nothing can be removed.
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('a learner not placed in a class sees the not-placed empty state',
      (tester) async {
    final w = _wire();
    await tester.pumpWidget(_host(LearnerResourcesScreen(
      repository: w.repo,
      studentId: 'stu-1',
      title: 'Resources',
    )));
    await tester.pumpAndSettle();

    expect(find.text('No resources yet'), findsOneWidget);
    expect(find.textContaining('Not placed in a class this year'),
        findsOneWidget);
  });

  testWidgets('a refused request (404) shows no resources and offers retry',
      (tester) async {
    final w = _wire()
      ..server.status = 404
      ..server.body = '{"message":"Not found"}';
    await tester.pumpWidget(_host(LearnerResourcesScreen(
      repository: w.repo,
      studentId: 'other-student',
      title: 'Resources',
    )));
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsNothing);
    expect(find.text('Copy link'), findsNothing);
    final before = w.server.requests.length;
    w.server
      ..status = 200
      ..body = _twoSubjects;
    await tester.tap(find.textContaining(RegExp('Retry|Try again')).first);
    await tester.pumpAndSettle();
    expect(w.server.requests.length, before + 1);
    expect(find.text('Algebra notes'), findsOneWidget);
  });
}

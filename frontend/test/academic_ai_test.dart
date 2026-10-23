import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academics/presentation/academic_ai_screen.dart';
import 'package:smartems/features/setup/domain/setup_models.dart';

/// Stubbed backend for the AI assistant: job creation, job polling, review actions.
class _AiServer implements HttpClientAdapter {
  final posts = <RequestOptions>[];
  int? failCreate;
  List<Map<String, dynamic>> assignments = [];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    ResponseBody json(int code, Object body) =>
        ResponseBody.fromString(jsonEncode(body), code, headers: {'content-type': ['application/json']});
    final path = o.uri.path;
    if (o.method == 'POST') {
      posts.add(o);
      if (path == '/api/ai/assignments') {
        return failCreate != null ? json(failCreate!, {'message': 'AI assistant is not configured'}) : json(202, {'jobId': 'job-1'});
      }
      return json(200, {});
    }
    if (path == '/api/workflow-jobs/job-1') {
      return json(200, {
        'id': 'job-1',
        'status': 'completed',
        'result': {
          'assignmentId': 'as-1',
          'proposal': {'title': 'Fractions practice', 'questions': ['Add 1/2 and 1/4', 'Simplify 6/8']},
        },
      });
    }
    if (path == '/api/assignments') return json(200, assignments);
    return json(404, {'message': 'not found'});
  }

  @override
  void close({bool force = false}) {}
}

const _year = AcademicYear(id: 'y1', name: '2025-26', startDate: '2025-04-01', endDate: '2026-03-31', current: true);

Future<_AiServer> _open(WidgetTester tester, {int? failCreate}) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server = _AiServer()..failCreate = failCreate;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(role: AppRole.teacher),
    home: AcademicAiScreen(
      dio: Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))..httpClientAdapter = server,
      subjects: const [Subject(id: 's1', name: 'Mathematics')],
      sections: const [Section(id: 'sec1', classId: 'c1', academicYearId: 'y1', name: '5-A')],
      classes: const [SchoolClass(id: 'c1', name: 'Grade 5')],
      years: const [_year],
    ),
  ));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _choose(WidgetTester tester, String label, String option) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.text('Create proposal'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('missing academic records: clear error, nothing sent', (tester) async {
    final server = await _open(tester);
    await _create(tester);
    expect(find.text('Choose the required academic records first.'), findsOneWidget);
    expect(server.posts, isEmpty);
  });

  testWidgets('DEF-20/21: proposal shown as readable lines; confirmed publish says what happened', (tester) async {
    final server = await _open(tester);
    await _choose(tester, 'Subject', 'Mathematics');
    await _choose(tester, 'Academic year', '2025-26');
    await _choose(tester, 'Section', '5-A');
    await tester.enterText(find.byType(TextField).last, 'Grade 5 fractions, addition and simplifying');
    await _create(tester);
    expect(server.posts.single.uri.path, '/api/ai/assignments');
    expect(server.posts.single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Title: Fractions practice'), findsOneWidget);
    expect(find.text('  - Add 1/2 and 1/4'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing, reason: 'no raw JSON');
    await tester.tap(find.text('Publish reviewed draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(server.posts.last.uri.path, '/api/assignments/as-1/publish');
    expect(find.text('Assignment published. Students can now see it.'), findsOneWidget);
    expect(find.text('Publish reviewed draft'), findsNothing);
  });

  testWidgets('cancelling the review confirmation sends nothing', (tester) async {
    final server = await _open(tester);
    await _choose(tester, 'Subject', 'Mathematics');
    await _choose(tester, 'Academic year', '2025-26');
    await _choose(tester, 'Section', '5-A');
    await _create(tester);
    final before = server.posts.length;
    await tester.tap(find.text('Publish reviewed draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(server.posts.length, before);
    expect(find.text('Publish reviewed draft'), findsOneWidget);
  });

  testWidgets('a server refusal shows the server message as an error', (tester) async {
    await _open(tester, failCreate: 400);
    await _choose(tester, 'Subject', 'Mathematics');
    await _choose(tester, 'Academic year', '2025-26');
    await _choose(tester, 'Section', '5-A');
    await _create(tester);
    expect(find.text('AI assistant is not configured'), findsOneWidget);
    expect(find.text('Create proposal'), findsOneWidget, reason: 'busy state cleared');
  });

  testWidgets('grading with no assignments shows an empty state, not a blank picker', (tester) async {
    await _open(tester);
    await _choose(tester, 'Task', 'Grading suggestion');
    expect(find.textContaining('No assignments yet.'), findsOneWidget);
  });

  test('proposalLines renders nested data without braces', () {
    expect(proposalLines({'dueDate': '2026-10-25', 'items': ['a', {'max_marks': 5}]}),
        ['Due date: 2026-10-25', 'Items:', '  - a', '  Max marks: 5']);
  });
}

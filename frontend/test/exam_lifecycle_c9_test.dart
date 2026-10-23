import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academics/data/academics_repository.dart';
import 'package:smartems/features/academics/domain/academic_models.dart';
import 'package:smartems/features/academics/domain/marks.dart';
import 'package:smartems/features/academics/presentation/exam_lifecycle_panel.dart';
import 'package:smartems/features/academics/presentation/result_governance.dart';
import 'package:smartems/features/academics/presentation/results_screen.dart';

/// C9 exam lifecycle in Flutter, against a fake adapter that answers like the
/// real routes: POST /api/exams/{id}/status, /publish, /withholding,
/// /corrections and GET .../versions.
class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  /// Status code and message for the next POST, to mimic a server refusal.
  int? failStatus;
  String failMessage = 'An exam can move from marking only to submitted';
  String sectionResultsJson = '[]';
  String studentResultJson = '{}';
  String versionsJson = '[]';

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;
    final body = o.data is Map ? (o.data as Map).cast<String, dynamic>() : null;
    if (o.method == 'GET') {
      if (path.contains('/results/section/')) return _raw(200, sectionResultsJson);
      if (path.endsWith('/versions')) return _raw(200, versionsJson);
      if (path.contains('/results/student/')) return _raw(200, studentResultJson);
    }
    if (failStatus != null) {
      final status = failStatus!;
      failStatus = null;
      return _raw(status, jsonEncode({'status': status, 'message': failMessage}));
    }
    if (path.endsWith('/status')) {
      return _raw(200, jsonEncode({'examId': 'exam-1', 'status': body?['status'], 'previousStatus': 'x'}));
    }
    if (path.endsWith('/publish')) {
      return _raw(200, '{"status":"published","reportCardsGenerated":0,"reportCardsQueued":2,"resultsPublished":2}');
    }
    if (path.endsWith('/withholding')) return _raw(200, '{"withheld":${body?['withheld']}}');
    if (path.endsWith('/corrections')) return _raw(200, '{"version":2}');
    return _raw(404, '{"message":"not found"}');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _raw(int status, String json) => ResponseBody.fromBytes(utf8.encode(json), status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

({_Server server, AcademicsRepository repo}) _wire() {
  final server = _Server();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server;
  return (server: server, repo: AcademicsRepository(dio));
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Exam _exam(ExamStatus status) => Exam(
      id: 'exam-1', name: 'Midterm', term: 'first_term', status: status,
      academicYearId: 'year-1', campusId: 'campus-a');

Future<ExamStatus?> _pumpPanel(WidgetTester tester, ({_Server server, AcademicsRepository repo}) w,
    ExamStatus status, {bool canManage = true}) async {
  ExamStatus? changed;
  await tester.pumpWidget(_host(ExamLifecyclePanel(
    repository: w.repo, exam: _exam(status), status: status, canManage: canManage,
    onChanged: (s) => changed = s)));
  await tester.pumpAndSettle();
  return changed;
}

Future<void> _confirm(WidgetTester tester, String action) async {
  await tester.tap(find.text(action).first);
  await tester.pumpAndSettle();
  // The confirmation dialog repeats the action label on its confirm button.
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
}

void main() {
  group('ExamStatus model', () {
    test('parses every server state and the pre-V55 names', () {
      expect(ExamStatus.parse('pending'), ExamStatus.draft);
      expect(ExamStatus.parse('marks_entry'), ExamStatus.marking);
      for (final s in ExamStatus.values) {
        expect(ExamStatus.parse(s.wire), s);
      }
      expect(ExamStatus.parse('something-new'), ExamStatus.submitted,
          reason: 'unknown states are treated as locked and unreleased');
    });

    test('the only path to publication is through approval', () {
      var s = ExamStatus.draft;
      final path = <ExamStatus>[s];
      while (s.next != null) {
        s = s.next!;
        path.add(s);
      }
      expect(path, ExamStatus.values);
      expect(ExamStatus.values.where((s) => s.next == ExamStatus.published), [ExamStatus.approved]);
      expect(ExamStatus.values.where((s) => s.isReleased), [ExamStatus.published, ExamStatus.archived]);
      expect(ExamStatus.values.where((s) => s.marksEditable),
          [ExamStatus.draft, ExamStatus.marking, ExamStatus.moderation]);
    });

    test('a missing mark is incomplete, never a pass and never zero', () {
      final r = StudentResult.fromJson({
        'student_id': 's', 'student_name': 'Ali', 'total_marks': '0.00', 'total_max': '0.00', 'percentage': '0.00',
        'result_status': 'pending',
        'subjects': [
          {'exam_subject_id': 'p1', 'subject_name': 'Science', 'max_marks': '100.00', 'passing_marks': '33.00',
           'marks_obtained': null, 'is_absent': false},
        ],
      });
      expect(r.status, ResultStatus.pending);
      expect(r.status.label, 'Incomplete');
      expect(r.subjects.single.marksObtained, isNull);
      expect(r.subjects.single.isMissing, isTrue);
      expect(r.subjects.single.failed, isFalse);
      expect(ResultStatus.parse('absent'), ResultStatus.absent);
    });
  });

  group('lifecycle panel', () {
    testWidgets('a marking exam offers "Submit for moderation", never "Publish results"', (tester) async {
      final w = _wire();
      await _pumpPanel(tester, w, ExamStatus.marking);
      expect(find.text('Submit for moderation'), findsOneWidget);
      expect(find.text('Publish results'), findsNothing);
    });

    testWidgets('each step posts exactly the next status', (tester) async {
      for (final (from, to, label) in [
        (ExamStatus.marking, 'submitted', 'Submit for moderation'),
        (ExamStatus.submitted, 'moderation', 'Start moderation'),
        (ExamStatus.moderation, 'approved', 'Approve results'),
        (ExamStatus.published, 'archived', 'Archive exam'),
      ]) {
        final w = _wire();
        await _pumpPanel(tester, w, from);
        await _confirm(tester, label);
        final posted = w.server.requests.where((r) => r.path == '/api/exams/exam-1/status').toList();
        expect(posted, hasLength(1), reason: label);
        expect((posted.single.data as Map)['status'], to);
        expect(w.server.requests.where((r) => r.path.endsWith('/publish')), isEmpty);
      }
    });

    testWidgets('publishing is offered only when approved, via the publish route', (tester) async {
      final w = _wire();
      await _pumpPanel(tester, w, ExamStatus.approved);
      expect(find.text('Publish results'), findsOneWidget);
      await _confirm(tester, 'Publish results');
      expect(w.server.requests.where((r) => r.path == '/api/exams/exam-1/publish'), hasLength(1));
      expect(find.textContaining('2 results published'), findsOneWidget);
    });

    testWidgets('a server refusal (409) is shown verbatim and the stage does not move', (tester) async {
      final w = _wire();
      w.server.failStatus = 409;
      ExamStatus? changed;
      await tester.pumpWidget(_host(ExamLifecyclePanel(
          repository: w.repo, exam: _exam(ExamStatus.marking), status: ExamStatus.marking,
          canManage: true, onChanged: (s) => changed = s)));
      await tester.pumpAndSettle();
      await _confirm(tester, 'Submit for moderation');
      expect(find.textContaining('An exam can move from marking only to submitted'), findsOneWidget);
      expect(changed, isNull);
      expect(find.text('Stage: Marking'), findsOneWidget);
    });

    testWidgets('an approval refused for missing marks (400) is explained, not swallowed', (tester) async {
      final w = _wire();
      w.server.failStatus = 400;
      w.server.failMessage = 'All marks must be entered before publishing (1 pending)';
      await _pumpPanel(tester, w, ExamStatus.moderation);
      await _confirm(tester, 'Approve results');
      expect(find.textContaining('1 pending'), findsOneWidget);
    });

    testWidgets('without exam.manage on the campus no action is offered', (tester) async {
      final w = _wire();
      await _pumpPanel(tester, w, ExamStatus.approved, canManage: false);
      expect(find.text('Publish results'), findsNothing);
      expect(find.textContaining('Only an exam manager'), findsOneWidget);
      expect(w.server.requests, isEmpty);
    });

    testWidgets('cancelling a confirmation sends nothing', (tester) async {
      final w = _wire();
      await _pumpPanel(tester, w, ExamStatus.approved);
      await tester.tap(find.text('Publish results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(w.server.requests, isEmpty);
    });
  });

  group('results governance', () {
    const pendingRow = '{"student_id":"s2","student_name":"Bilal","total_marks":0.00,"total_max":0.00,'
        '"percentage":0.00,"result_status":"pending","withheld":false}';
    const withheldRow = '{"student_id":"s3","student_name":"Hina","total_marks":50.00,"total_max":100.00,'
        '"percentage":50.00,"result_status":"pass","withheld":true,"withheld_reason":"Board review",'
        '"current_version":null}';
    const correctedRow = '{"student_id":"s1","student_name":"Ayesha","total_marks":75.00,"total_max":100.00,'
        '"percentage":75.00,"result_status":"pass","withheld":false,"current_version":2}';

    testWidgets('results say Incomplete, Withheld and Corrected in words', (tester) async {
      final w = _wire();
      w.server.sectionResultsJson = '[$pendingRow,$withheldRow,$correctedRow]';
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: ResultsScreen(repository: w.repo, exam: _exam(ExamStatus.published), sectionId: 'sec', canManage: true)));
      await tester.pumpAndSettle();
      expect(find.text('Incomplete'), findsOneWidget);
      expect(find.text('Withheld: Board review'), findsOneWidget);
      expect(find.text('Corrected · version 2'), findsOneWidget);
      expect(find.text('Release result'), findsOneWidget);
      expect(find.text('Official correction'), findsNWidgets(3));
    });

    testWidgets('staff actions are hidden without exam.manage', (tester) async {
      final w = _wire();
      w.server.sectionResultsJson = '[$correctedRow]';
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: ResultsScreen(repository: w.repo, exam: _exam(ExamStatus.published), sectionId: 'sec')));
      await tester.pumpAndSettle();
      expect(find.text('Withhold result'), findsNothing);
      expect(find.text('Official correction'), findsNothing);
    });

    testWidgets('withholding requires a reason and posts it', (tester) async {
      final w = _wire();
      final row = StudentResult.fromJson(jsonDecode(AcademicJson.quoteNumbers(correctedRow)) as Map<String, dynamic>);
      var changed = 0;
      await tester.pumpWidget(_host(ResultGovernanceActions(
          repository: w.repo, exam: _exam(ExamStatus.moderation), result: row, onChanged: () => changed++)));
      await tester.pumpAndSettle();
      expect(find.text('Official correction'), findsNothing, reason: 'corrections apply only after publication');
      await tester.tap(find.text('Withhold result'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Withhold');
      expect(tester.widget<TextButton>(confirm).onPressed, isNull, reason: 'empty reason');
      await tester.enterText(find.byType(TextField), 'Paper under review');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final posted = w.server.requests.singleWhere((r) => r.path.endsWith('/withholding'));
      expect((posted.data as Map)['withheld'], isTrue);
      expect((posted.data as Map)['reason'], 'Paper under review');
      expect(changed, 1);
    });

    testWidgets('an official correction needs a reason and records a new version', (tester) async {
      final w = _wire();
      w.server.studentResultJson = '{"student_id":"s1","student_name":"Ayesha","total_marks":70.00,'
          '"total_max":100.00,"percentage":70.00,"result_status":"pass","subjects":[{"exam_subject_id":"paper-1",'
          '"subject_name":"Science","max_marks":100.00,"passing_marks":33.00,"marks_obtained":70.00,'
          '"is_absent":false}]}';
      final row = StudentResult.fromJson(jsonDecode(AcademicJson.quoteNumbers(correctedRow)) as Map<String, dynamic>);
      await tester.pumpWidget(_host(ResultGovernanceActions(
          repository: w.repo, exam: _exam(ExamStatus.published), result: row, onChanged: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Official correction'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Record correction');
      await tester.enterText(find.byType(TextField).at(0), '75');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(save).onPressed, isNull, reason: 'reason required');
      await tester.enterText(find.byType(TextField).at(1), 'Totalling error');
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final posted = w.server.requests.singleWhere((r) => r.path.endsWith('/corrections'));
      final data = posted.data as Map;
      expect(data['examSubjectId'], 'paper-1');
      expect(data['marksObtained'], Marks.parse('75').toBackendString());
      expect(data['reason'], 'Totalling error');
    });

    testWidgets('version history marks the superseded and the in-force version', (tester) async {
      final w = _wire();
      w.server.versionsJson = jsonEncode([
        {'version': 1, 'snapshot': jsonEncode({'total_marks': '70.00'}), 'reason': null, 'createdAt': 't1'},
        {'version': 2, 'snapshot': jsonEncode({'total_marks': '75.00'}), 'reason': 'Totalling error', 'createdAt': 't2'},
      ]);
      final row = StudentResult.fromJson(jsonDecode(AcademicJson.quoteNumbers(correctedRow)) as Map<String, dynamic>);
      await tester.pumpWidget(_host(ResultGovernanceActions(
          repository: w.repo, exam: _exam(ExamStatus.published), result: row, onChanged: () {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Version history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Version 1 (superseded) · total 70.00'), findsOneWidget);
      expect(find.textContaining('Version 2 (in force) · total 75.00 · Totalling error'), findsOneWidget);
    });
  });
}

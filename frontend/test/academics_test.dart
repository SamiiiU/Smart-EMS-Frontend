import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academics/data/academics_repository.dart';
import 'package:smartems/features/academics/domain/academic_models.dart';
import 'package:smartems/features/academics/domain/marks.dart';
import 'package:smartems/features/academics/presentation/academics_home_screen.dart';
import 'package:smartems/features/academics/presentation/exam_papers_screen.dart';
import 'package:smartems/features/academics/presentation/exam_setup_screen.dart';
import 'package:smartems/features/academics/presentation/marks_entry_screen.dart';
import 'package:smartems/features/academics/presentation/remarks_screen.dart';
import 'package:smartems/features/academics/presentation/report_card_screen.dart';
import 'package:smartems/features/academics/presentation/results_screen.dart';
import 'package:smartems/features/academics/presentation/syllabus_screen.dart';
import 'package:smartems/features/academics/presentation/unavailable_screens.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';

import 'package:smartems/features/setup/data/setup_repository.dart';
import 'package:smartems/features/setup/domain/setup_models.dart';

/// A stub of the academic endpoints with this backend's REAL quirks:
///
///  - marks and percentages as bare JSON numbers with two decimals;
///  - snake_case exam responses against camelCase remarks;
///  - a mark POST returning the whole recomputed result;
///  - papers that cannot be listed back (405) and 409 on a duplicate;
///  - publish locking the marks.
///
/// Bodies are raw JSON TEXT, because `jsonEncode(85.5)` cannot produce
/// `85.50` and that exact shape is the thing under test.
class _AcademicServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  final List<String> exams = [];
  String sectionResultsJson = '[]';
  String studentResultJson = '{}';
  String chaptersJson = '[]';
  String progressJson = '{"percentage":0.00,"coveredTopics":0,'
      '"totalTopics":0,"coveredChapters":0,"totalChapters":0,"chapters":[]}';
  final List<String> remarks = [];

  /// Set to make the next write fail the way the live API does.
  int? failStatus;
  String failMessage = 'Conflicts with existing data';

  String? reportCardJson;
  Object? lastBody;
  int _id = 0;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;
    final body = o.data is Map ? (o.data as Map).cast<String, dynamic>() : null;

    if (o.method == 'GET') {
      if (path == '/api/exams') return _raw(200, '[${exams.join(',')}]');
      if (path.contains('/results/section/')) {
        return _raw(200, sectionResultsJson);
      }
      if (path.contains('/results/student/')) {
        return _raw(200, studentResultJson);
      }
      if (path.contains('/report-card/')) {
        return reportCardJson == null
            ? _raw(404, '{"message":"ReportCard not found"}')
            : _raw(200, reportCardJson!);
      }
      if (path.startsWith('/api/remarks/')) {
        return _raw(200, '[${remarks.join(',')}]');
      }
      if (path == '/api/syllabus/chapters') return _raw(200, chaptersJson);
      if (path == '/api/syllabus/progress') return _raw(200, progressJson);
      // Shared setup reads the hub needs.
      if (path == '/api/campuses') {
        return _raw(200, '[{"id":"campus-1","name":"Main"}]');
      }
      if (path == '/api/academic-years') {
        return _raw(
          200,
          '{"content":[{"id":"year-1","name":"2025-26","startDate":'
          '"2025-08-01","endDate":"2026-05-31","current":true}],'
          '"totalElements":1}',
        );
      }
      if (path == '/api/classes') {
        return _raw(200,
            '{"content":[{"id":"class-1","name":"Grade 5","levelOrder":5}]}');
      }
      if (path == '/api/sections') {
        return _raw(
          200,
          '{"content":[{"id":"section-1","classId":"class-1","name":"A",'
          '"academicYearId":"year-1"}]}',
        );
      }
      if (path == '/api/subjects') {
        return _raw(200,
            '{"content":[{"id":"subject-1","name":"Mathematics"}]}');
      }
      if (path.startsWith('/api/enrollments/section/')) {
        return _raw(200, '{"content":[$rosterJson]}');
      }
      if (path == '/api/students') return _raw(200, '{"content":[$studentsJson]}');
      return _raw(404, '{"message":"no route"}');
    }

    if (o.method == 'POST') {
      if (failStatus != null) {
        final status = failStatus!;
        failStatus = null;
        return _raw(status, '{"message":"$failMessage"}');
      }
      if (path == '/api/exams') {
        final row = '{"id":"exam-${_id++}","name":"${body?['name']}",'
            '"term":${body?['term'] == null ? 'null' : '"${body?['term']}"'},'
            '"status":"pending","result_date":null,'
            '"academic_year_id":"${body?['academicYearId']}"}';
        exams.add(row);
        return _raw(201, row);
      }
      if (path.endsWith('/subjects')) {
        lastBody = body;
        return _raw(
          201,
          '{"id":"paper-${_id++}","exam_id":"exam-0",'
          '"section_id":"${body?['sectionId']}",'
          '"subject_id":"${body?['subjectId']}",'
          '"max_marks":${body?['maxMarks']},'
          '"passing_marks":${body?['passingMarks']}}',
        );
      }
      if (path.endsWith('/marks/bulk')) {
        lastBody = o.data;
        final rows = (o.data as List).length;
        return _raw(200,
            '{"errors":[],"successCount":$rows,"errorCount":0}');
      }
      if (path.endsWith('/marks')) {
        lastBody = body;
        return _raw(
          200,
          '{"exam_id":"exam-0","student_id":"${body?['studentId']}",'
          '"total_marks":85.00,"total_max":100.00,"percentage":85.00,'
          '"grade":"A","grade_point":3.70,"position":1,'
          '"result_status":"pass","published_at":null}',
        );
      }
      if (path.endsWith('/publish')) {
        return _raw(200,
            '{"reportCardsGenerated":1,"resultsPublished":1,"status":"published"}');
      }
      if (path == '/api/remarks') {
        lastBody = body;
        final row = '{"id":"remark-${_id++}",'
            '"studentId":"${body?['studentId']}","studentName":"Ali Khan",'
            '"remarkType":"${body?['remarkType']}","body":"${body?['body']}",'
            '"isParentVisible":${body?['isParentVisible']},'
            '"remarkDate":"2026-09-25","authorName":"Admin User"}';
        remarks.add(row);
        return _raw(201, row);
      }
      if (path == '/api/syllabus/chapters') {
        return _raw(
          201,
          '{"id":"chapter-${_id++}","name":"${body?['name']}","sort_order":1,'
          '"topics":[]}',
        );
      }
      if (path == '/api/syllabus/topics') {
        return _raw(201,
            '{"id":"topic-${_id++}","name":"${body?['name']}","sort_order":1}');
      }
      if (path == '/api/syllabus/coverage') {
        lastBody = body;
        return _raw(201,
            '{"status":"${body?['status']}","idempotent":false,"logId":"l1"}');
      }
    }
    return _raw(404, '{"message":"no route"}');
  }

  /// A 40-student section, the size this screen is designed for.
  String rosterJson = List.generate(
    40,
    (i) => '{"studentId":"stu-$i","sectionId":"section-1",'
        '"status":"enrolled","rollNumber":"${i + 1}"}',
  ).join(',');

  String studentsJson = List.generate(
    40,
    (i) => '{"id":"stu-$i","firstName":"Student","lastName":"${i + 1}"}',
  ).join(',');

  @override
  void close({bool force = false}) {}
}

ResponseBody _raw(int status, String json) => ResponseBody.fromBytes(
      utf8.encode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

typedef _Wired = ({Dio dio, _AcademicServer server, AcademicsRepository repo});

_Wired _wire() {
  final server = _AcademicServer();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return (dio: dio, server: server, repo: AcademicsRepository(dio));
}

Widget _host(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark
          ? AppTheme.dark(role: AppRole.admin)
          : AppTheme.light(role: AppRole.admin),
      home: child,
    );

const _year = AcademicYear(
  id: 'year-1',
  name: '2025-26',
  startDate: '2025-08-01',
  endDate: '2026-05-31',
  current: true,
);
const _class = SchoolClass(id: 'class-1', name: 'Grade 5', levelOrder: 5);
const _section = Section(
  id: 'section-1',
  classId: 'class-1',
  academicYearId: 'year-1',
  name: 'A',
);
const _subject = Subject(id: 'subject-1', name: 'Mathematics');

final _paper = ExamPaper(
  id: 'paper-1',
  examId: 'exam-1',
  sectionId: 'section-1',
  subjectId: 'subject-1',
  maxMarks: Marks.parse('100'),
  passingMarks: Marks.parse('40'),
  subjectName: 'Mathematics',
  sectionName: 'Grade 5 A',
);

const _exam = Exam(
  id: 'exam-1',
  name: 'First Term',
  term: 'first_term',
  status: ExamStatus.pending,
  academicYearId: 'year-1',
);

void main() {
  group('the decoding door', () {
    test('a mark from the wire becomes an exact value', () async {
      final w = _wire();
      w.server.sectionResultsJson = '[{"student_id":"s1",'
          '"student_name":"Ali Khan","total_marks":85.50,"total_max":100.00,'
          '"percentage":85.50,"grade":"A","grade_point":3.70,"position":1,'
          '"result_status":"pass"}]';

      final rows = await w.repo.loadSectionResults(
        examId: 'exam-1',
        sectionId: 'section-1',
      );
      expect(rows.single.totalMarks, Marks.parse('85.50'));
      expect(rows.single.totalMarks.hundredths, 8550);
      expect(rows.single.gradePoint, Marks.parse('3.70'));
    });

    test('the year is always sent when listing exams', () async {
      final w = _wire();
      await w.repo.loadExams(academicYearId: 'year-1');
      expect(
        w.server.requests.last.uri.queryParameters['academicYearId'],
        'year-1',
      );
    });
  });

  group('writes', () {
    test('an exam carries an explicit academic year, never a resolved one',
        () async {
      final w = _wire();
      await w.repo.createExam(
        campusId: 'campus-1',
        academicYearId: 'year-1',
        name: 'First Term',
        term: ExamTerm.firstTerm,
      );
      final body = w.server.requests.last.data as Map;
      expect(body['academicYearId'], 'year-1');
      expect(body['term'], 'first_term');
      // No gradeSchemeId: there is no endpoint that can produce one, so
      // sending a value would be a guess.
      expect(body.containsKey('gradeSchemeId'), isFalse);
    });

    test('a paper sends its marks as exact decimal text', () async {
      final w = _wire();
      await w.repo.createPaper(
        examId: 'exam-1',
        sectionId: 'section-1',
        subjectId: 'subject-1',
        maxMarks: Marks.parse('100'),
        passingMarks: Marks.parse('33.5'),
      );
      final body = w.server.requests.last.data as Map;
      expect(body['maxMarks'], '100.00');
      expect(body['passingMarks'], '33.50');
      expect(body['maxMarks'], isA<String>());
    });

    test('bulk marks are sent as a BARE ARRAY, not an object', () async {
      final w = _wire();
      await w.repo.saveMarks(
        examSubjectId: 'paper-1',
        entries: [
          const MarkEntry(studentId: 's1', studentName: 'A', text: '85'),
          const MarkEntry(studentId: 's2', studentName: 'B', isAbsent: true),
        ],
      );
      // An object answers "Malformed request body" on the live API.
      expect(w.server.lastBody, isA<List<dynamic>>());
      final rows = w.server.lastBody! as List;
      expect(rows.length, 2);
      expect((rows[0] as Map)['marksObtained'], '85.00');
      expect((rows[1] as Map)['isAbsent'], isTrue);
      // An absent student carries no number at all.
      expect((rows[1] as Map).containsKey('marksObtained'), isFalse);
    });

    test('rows with nothing entered are left out, not sent as zero', () async {
      final w = _wire();
      await w.repo.saveMarks(
        examSubjectId: 'paper-1',
        entries: [
          const MarkEntry(studentId: 's1', studentName: 'A', text: '85'),
          const MarkEntry(studentId: 's2', studentName: 'B'),
        ],
      );
      // An unentered mark and a mark of zero are different facts.
      expect((w.server.lastBody! as List).length, 1);
    });

    test('the backend’s own message is surfaced', () async {
      final w = _wire();
      w.server.failStatus = 400;
      w.server.failMessage = 'marksObtained 150 exceeds max 100.00';

      final outcome = await w.repo.saveMark(
        examSubjectId: 'paper-1',
        studentId: 's1',
        marksObtained: Marks.parse('150'),
      );
      expect(outcome.result, isNull);
      expect(outcome.error, contains('exceeds max 100.00'));
    });

    test('a report card 404 is "not ready", not an error', () async {
      final w = _wire();
      final card = await w.repo.loadReportCard(
        examId: 'exam-1',
        studentId: 's1',
      );
      expect(card, isNull);
    });
  });

  group('marks entry — attendance ergonomics', () {
    Widget screen(_Wired w,
            {bool locked = false}) =>
        _host(MarksEntryScreen(
          repository: w.repo,
          paper: _paper,
          examName: 'First Term',
          marksLocked: locked,
        ));

    testWidgets('a 40-student section is entered with one field per student',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      // Forty rows, forty fields — one interaction per student, the same
      // budget as marking a roll call.
      expect(find.byType(MarkRow), findsWidgets);
      expect(find.text('0 of 40 entered'), findsOneWidget);
    });

    testWidgets('the running summary is visible without scrolling',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      expect(find.text('0 of 40 entered'), findsOneWidget);
      expect(find.text('40 left'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '85');
      await tester.pumpAndSettle();

      // Still on screen, without touching the scroll position.
      expect(find.text('1 of 40 entered'), findsOneWidget);
      expect(find.text('39 left'), findsOneWidget);
    });

    testWidgets('validation runs as they type, on the offending row',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '150');
      await tester.pumpAndSettle();

      // Named against the paper's maximum, on the row, immediately.
      expect(find.text('Over 100'), findsOneWidget);
      expect(find.text('1 needs fixing'), findsOneWidget);
    });

    testWidgets('a row that needs fixing blocks the save', (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '150');
      await tester.pumpAndSettle();

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Save marks'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Enter moves to the next student and does NOT submit',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '85');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // A stray Enter halfway down a class must never save.
      expect(
        w.server.requests.where((r) => r.path.contains('marks')),
        isEmpty,
      );
    });

    testWidgets('absent is a toggle and clears the number', (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '85');
      await tester.pumpAndSettle();
      expect(find.text('1 of 40 entered'), findsOneWidget);

      // Tap the toggle inside the FIRST row, so this cannot drift onto
      // another student's control.
      final toggle = find.descendant(
        of: find.byType(MarkRow).first,
        matching: find.text('Absent'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // Still entered — absent IS an entry — and the number is gone, so the
      // two can never disagree about the same student.
      expect(find.text('1 of 40 entered'), findsOneWidget);
      final row = tester.widget<MarkRow>(find.byType(MarkRow).first);
      expect(row.entry.isAbsent, isTrue);
      expect(row.controller.text, isEmpty);
    });

    testWidgets('it says marks cannot be read back', (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no way to read them back'),
        findsOneWidget,
      );
    });

    testWidgets('a published exam says the marks are locked', (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w, locked: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('locked and can no longer be changed'),
          findsOneWidget);
    });

    testWidgets('saving sends every entered row', (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '85');
      await tester.enterText(find.byType(TextField).at(1), '70');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save marks'));
      await tester.pumpAndSettle();

      expect((w.server.lastBody! as List).length, 2);
      expect(find.text('2 marks saved.'), findsOneWidget);
    });
  });

  group('exams', () {
    testWidgets('only the six accepted terms are offered', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(ExamSetupScreen(
        repository: w.repo,
        year: _year,
        campusId: 'campus-1',
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add an exam'));
      await tester.pumpAndSettle();

      for (final term in ExamTerm.values) {
        expect(find.text(term.label), findsOneWidget);
      }
      // Values the backend rejects are not offered at all.
      expect(find.text('Quarterly'), findsNothing);
      expect(find.text('Half yearly'), findsNothing);
    });

    testWidgets('the year being written to is named', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(ExamSetupScreen(
        repository: w.repo,
        year: _year,
        campusId: 'campus-1',
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('2025-26'), findsOneWidget);
    });

    testWidgets('papers warn that they cannot be found again', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(ExamPapersScreen(
        repository: w.repo,
        exam: _exam,
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot list papers back'), findsOneWidget);
    });

    testWidgets('a duplicate paper explains that it cannot be reopened',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(ExamPapersScreen(
        repository: w.repo,
        exam: _exam,
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      w.server.failStatus = 409;
      await tester.tap(find.text('Add a paper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already has a paper'), findsOneWidget);
      expect(find.textContaining('no way to look a paper up'), findsOneWidget);
    });

    testWidgets('publishing is confirmed and stated as irreversible',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(ExamPapersScreen(
        repository: w.repo,
        exam: _exam,
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Publish results'));
      await tester.pumpAndSettle();

      expect(find.text('Publish this exam?'), findsOneWidget);
      expect(find.textContaining('marks are locked permanently'),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        w.server.requests.where((r) => r.path.endsWith('/publish')),
        isEmpty,
      );
    });
  });

  group('results', () {
    testWidgets('failures are at the top, not the first name alphabetically',
        (tester) async {
      final w = _wire();
      w.server.sectionResultsJson = '['
          '{"student_id":"a","student_name":"Aisha","total_marks":95.00,'
          '"total_max":100.00,"percentage":95.00,"grade":"A",'
          '"grade_point":4.00,"position":1,"result_status":"pass"},'
          '{"student_id":"z","student_name":"Zara","total_marks":20.00,'
          '"total_max":100.00,"percentage":20.00,"grade":"F",'
          '"grade_point":0.00,"position":2,"result_status":"fail"}]';

      await tester.pumpWidget(_host(ResultsScreen(
        repository: w.repo,
        exam: _exam,
        sectionId: 'section-1',
        sectionName: 'Grade 5 A',
      )));
      await tester.pumpAndSettle();

      final names = tester
          .widgetList<ResultRow>(find.byType(ResultRow))
          .map((r) => r.result.studentName)
          .toList();
      expect(names.first, 'Zara');
    });

    testWidgets('pass and fail are words, not only a colour', (tester) async {
      final w = _wire();
      w.server.sectionResultsJson = '['
          '{"student_id":"z","student_name":"Zara","total_marks":20.00,'
          '"total_max":100.00,"percentage":20.00,"grade":"F",'
          '"grade_point":0.00,"position":1,"result_status":"fail"}]';

      await tester.pumpWidget(_host(ResultsScreen(
        repository: w.repo,
        exam: _exam,
        sectionId: 'section-1',
      )));
      await tester.pumpAndSettle();

      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
    });
  });

  group('report card', () {
    testWidgets('it shows the card and offers no download or print',
        (tester) async {
      final w = _wire();
      w.server.studentResultJson =
          '{"student_id":"s1","student_name":"Ali Khan",'
          '"total_marks":85.00,"total_max":100.00,"percentage":85.00,'
          '"grade":"A","grade_point":3.70,"position":1,'
          '"result_status":"pass","subjects":[{"subject_name":"Maths",'
          '"max_marks":100.00,"passing_marks":40.00,"marks_obtained":85.00,'
          '"is_absent":false,"grade":"A"}]}';
      w.server.reportCardJson =
          '{"generatedAt":"2026-09-25","available":true,"status":"generated"}';

      await tester.pumpWidget(_host(ReportCardScreen(
        repository: w.repo,
        exam: _exam,
        studentId: 's1',
        studentName: 'Ali Khan',
      )));
      await tester.pumpAndSettle();

      expect(find.text('Maths'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.textContaining('cannot be downloaded or printed'),
          findsOneWidget);
      expect(find.text('Download'), findsNothing);
      expect(find.text('Print'), findsNothing);
    });
  });

  group('remarks — the privacy copy', () {
    Widget screen(_Wired w) =>
        _host(RemarksScreen(
          repository: w.repo,
          sectionId: 'section-1',
          sectionName: 'Grade 5 A',
        ));

    testWidgets('the consequence is stated beside the control, not in a tooltip',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write a remark'));
      await tester.pumpAndSettle();

      expect(find.byType(ParentVisibilityControl), findsOneWidget);
      expect(find.text('The parent will not see this remark.'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('it never claims a remark is private in general',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write a remark'));
      await tester.pumpAndSettle();

      // The backend does NOT hide these from the student — saying
      // "private" or "staff only" would be false and a teacher acting on it
      // could be badly caught out.
      expect(find.textContaining('so can the student'), findsOneWidget);
      expect(find.textContaining('Only you can see'), findsNothing);
      expect(find.textContaining('staff only'), findsNothing);
      expect(find.textContaining('Private'), findsNothing);
    });

    testWidgets('turning the toggle on changes what it promises',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write a remark'));
      await tester.pumpAndSettle();
      // The control sits below a chip per student, so it has to be brought
      // into view before it can be tapped.
      await tester.ensureVisible(find.byType(ParentVisibilityControl));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('The parent will see this remark in their app.'),
          findsOneWidget);
    });

    testWidgets('every listed remark says who can see it', (tester) async {
      final w = _wire();
      w.server.remarks.add(
        '{"id":"r1","studentId":"s1","studentName":"Ali Khan",'
        '"remarkType":"general","body":"Doing well","isParentVisible":false,'
        '"remarkDate":"2026-09-25","authorName":"Admin User"}',
      );
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      expect(find.text('Not shown to parent'), findsOneWidget);
    });

    testWidgets('the flag is sent as chosen, never filtered locally',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(screen(w));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write a remark'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Needs support');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final body = w.server.lastBody! as Map;
      expect(body['isParentVisible'], isFalse);
      expect(body['body'], 'Needs support');
    });
  });

  group('syllabus', () {
    testWidgets('progress is the server’s percentage, not covered ÷ total',
        (tester) async {
      final w = _wire();
      w.server.chaptersJson = '[{"id":"c1","name":"Algebra","sort_order":1,'
          '"topics":[{"id":"t1","name":"Quadratics","sort_order":1}]}]';
      // 1 of 3 is 33.33…%, and the server says 40.
      w.server.progressJson = '{"percentage":40.00,"coveredTopics":1,'
          '"totalTopics":3,"coveredChapters":0,"totalChapters":1,'
          '"chapters":[{"name":"Algebra","status":"pending","topics":3,'
          '"covered":1}]}';

      await tester.pumpWidget(_host(SyllabusScreen(
        repository: w.repo,
        year: _year,
        classes: const [_class],
        sections: const [_section],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      expect(find.text('40% covered'), findsOneWidget);
      expect(find.text('33.33% covered'), findsNothing);
      expect(find.text('1 of 3 topics · 0 of 1 chapters'), findsOneWidget);
    });

    testWidgets('only the two accepted coverage statuses are offered',
        (tester) async {
      final w = _wire();
      w.server.chaptersJson = '[{"id":"c1","name":"Algebra","sort_order":1,'
          '"topics":[{"id":"t1","name":"Quadratics","sort_order":1}]}]';

      await tester.pumpWidget(_host(SyllabusScreen(
        repository: w.repo,
        year: _year,
        classes: const [_class],
        sections: const [_section],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Covered'), findsOneWidget);
      expect(find.text('Partly covered'), findsOneWidget);
      // `pending` is rejected by the backend, so it is never offered.
      expect(find.text('Pending'), findsNothing);
    });

    testWidgets('marking a topic sends the lowercase wire value',
        (tester) async {
      final w = _wire();
      w.server.chaptersJson = '[{"id":"c1","name":"Algebra","sort_order":1,'
          '"topics":[{"id":"t1","name":"Quadratics","sort_order":1}]}]';

      await tester.pumpWidget(_host(SyllabusScreen(
        repository: w.repo,
        year: _year,
        classes: const [_class],
        sections: const [_section],
        subjects: const [_subject],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Covered'));
      await tester.pumpAndSettle();

      expect((w.server.lastBody! as Map)['status'], 'covered');
    });
  });

  group('the screens with no backend', () {
    testWidgets('grade schemes explains that grading works but is fixed',
        (tester) async {
      await tester.pumpWidget(_host(const GradeSchemesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Grades are applied automatically'), findsOneWidget);
      expect(find.textContaining('cannot be viewed or changed'), findsOneWidget);
      // No form that could not save, and no disabled button.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('subject resources says what to do instead', (tester) async {
      await tester.pumpWidget(_host(const SubjectResourcesScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('no way to receive an uploaded file'),
          findsOneWidget);
      expect(find.textContaining('Share material through the diary'),
          findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('the academics hub', () {
    Widget hub(_Wired w) =>
        _host(AcademicsHomeScreen(
          academics: w.repo,
          setup: SetupRepository(w.dio),
          admin: AdminRepository(w.dio),
        ));

    testWidgets('every step is reachable when its dependencies exist',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(hub(w));
      await tester.pumpAndSettle();

      expect(find.text('Exams'), findsOneWidget);
      expect(find.text('Remarks'), findsOneWidget);
      expect(find.text('Syllabus'), findsOneWidget);
      // Both no-backend screens are listed, not hidden.
      expect(find.text('Grade scheme'), findsOneWidget);
      expect(find.text('Subject resources'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
    });
  });

  group('both themes, and no overflow', () {
    for (final dark in [false, true]) {
      testWidgets('every academic screen renders in ${dark ? 'dark' : 'light'}',
          (tester) async {
        final w = _wire();
        w.server.studentResultJson =
            '{"student_id":"s1","student_name":"Ali Khan",'
            '"total_marks":85.00,"total_max":100.00,"percentage":85.00,'
            '"grade":"A","grade_point":3.70,"position":1,'
            '"result_status":"pass","subjects":[]}';
        w.server.sectionResultsJson = '[{"student_id":"s1",'
            '"student_name":"Ali Khan","total_marks":85.00,'
            '"total_max":100.00,"percentage":85.00,"grade":"A",'
            '"grade_point":3.70,"position":1,"result_status":"pass"}]';

        for (final entry in _allScreens(w).entries) {
          await tester.pumpWidget(_host(entry.value, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${entry.key} threw in ${dark ? 'dark' : 'light'}');
        }
      });
    }

    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('no academic screen overflows at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final w = _wire();
        w.server.sectionResultsJson = '[{"student_id":"s1",'
            '"student_name":"Muhammad Abdul Rehman","total_marks":85.50,'
            '"total_max":100.00,"percentage":85.50,"grade":"A",'
            '"grade_point":3.70,"position":1,"result_status":"pass"}]';

        for (final entry in _allScreens(w).entries) {
          await tester.pumpWidget(_host(entry.value));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${entry.key} overflowed at ${width.toInt()}px');
        }
      });
    }

    testWidgets('marks entry survives a large text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final w = _wire();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MarksEntryScreen(
            repository: w.repo,
            paper: _paper,
            examName: 'First Term',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('the absent toggle announces its state', (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(MarksEntryScreen(
        repository: w.repo,
        paper: _paper,
        examName: 'First Term',
      )));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Student 1 absent')), findsOneWidget);
    });

    testWidgets('a result row carries its outcome in its label',
        (tester) async {
      final w = _wire();
      w.server.sectionResultsJson = '[{"student_id":"z",'
          '"student_name":"Zara","total_marks":20.00,"total_max":100.00,'
          '"percentage":20.00,"grade":"F","grade_point":0.00,"position":1,'
          '"result_status":"fail"}]';

      await tester.pumpWidget(_host(ResultsScreen(
        repository: w.repo,
        exam: _exam,
        sectionId: 'section-1',
      )));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Zara.*failed')), findsOneWidget);
    });
  });
}

Map<String, Widget> _allScreens(_Wired w) =>
    {
      'hub': AcademicsHomeScreen(
        academics: w.repo,
        setup: SetupRepository(w.dio),
        admin: AdminRepository(w.dio),
      ),
      'grades': const GradeSchemesScreen(),
      'resources': const SubjectResourcesScreen(),
      'exams': ExamSetupScreen(
        repository: w.repo,
        year: _year,
        campusId: 'campus-1',
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      ),
      'papers': ExamPapersScreen(
        repository: w.repo,
        exam: _exam,
        sections: const [_section],
        classes: const [_class],
        subjects: const [_subject],
      ),
      'marks': MarksEntryScreen(
        repository: w.repo,
        paper: _paper,
        examName: 'First Term',
      ),
      'results': ResultsScreen(
        repository: w.repo,
        exam: _exam,
        sectionId: 'section-1',
      ),
      'reportCard': ReportCardScreen(
        repository: w.repo,
        exam: _exam,
        studentId: 's1',
        studentName: 'Ali Khan',
      ),
      'remarks': RemarksScreen(
        repository: w.repo,
        sectionId: 'section-1',
        sectionName: 'Grade 5 A',
      ),
      'syllabus': SyllabusScreen(
        repository: w.repo,
        year: _year,
        classes: const [_class],
        sections: const [_section],
        subjects: const [_subject],
      ),
    };

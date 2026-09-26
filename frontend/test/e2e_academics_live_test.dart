import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/academics/data/academics_repository.dart';
import 'package:smartems/features/academics/domain/academic_models.dart';
import 'package:smartems/features/academics/domain/marks.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';

/// T15's end-to-end proof, against the REAL backend.
///
/// Walks the academic loop the way the screens do — exam → paper → marks →
/// results → publish → report card, plus a remark and a syllabus topic —
/// through `AcademicsRepository`, the exact code path every academic screen
/// uses. No curl, and no hand-written request bodies.
///
/// ```
/// flutter test test/e2e_academics_live_test.dart --dart-define=LIVE=true
/// ```
/// Without the flag it skips, and skips again if the backend is down.
///
/// 🔴 **Same honest limit as T13 and T14: this drives the repository, not
/// the widgets.** `flutter test` installs a fake clock, so a real HTTP call
/// started by a widget never completes. Driving the actual screens live
/// needs `integration_test`, which this project has never set up. The
/// screens are covered hermetically in `academics_test.dart`; the manual
/// pass named in HANDOFF.md is the human half.
///
/// 🔴 **This test cannot clean up after itself.** There is no delete for an
/// exam, a paper, a mark, a chapter, a topic or a coverage log, and
/// publishing cannot be undone. Every run leaves permanent rows in
/// `test-school`, all prefixed `E2E`. Remarks ARE deleted, because they are
/// the one thing in this batch that can be.
const _base = 'http://localhost:8080';

const bool _enabled = bool.fromEnvironment('LIVE');

Future<bool> _backendUp() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final req = await client.getUrl(Uri.parse('$_base/health'));
    final res = await req.close();
    await res.drain<void>();
    client.close();
    return res.statusCode == 200;
  } on Object {
    return false;
  }
}

void main() {
  test('an exam is set up, marked, published and reported, through the app’s '
      'own code', () async {
    if (!_enabled) {
      markTestSkipped('live test — pass --dart-define=LIVE=true to run it');
      return;
    }
    if (!await _backendUp()) {
      markTestSkipped('backend not running on $_base');
      return;
    }

    final dio = Dio(BaseOptions(baseUrl: _base));
    final login = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'institutionCode': 'test-school',
        'username': 'admin',
        'password': 'Test1234!',
      },
    );
    dio.options.headers['Authorization'] =
        'Bearer ${login.data!['accessToken']}';

    final academics = AcademicsRepository(dio);
    final setup = SetupRepository(dio);
    final admin = AdminRepository(dio);

    final campusId = (await admin.loadCampusIds()).first;
    final stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);

    // The year is taken explicitly and never left to the server — the
    // `current` flag on this backend points at an EXPIRED year.
    final years = await setup.loadYears();
    final year = years.firstWhere((y) => y.current, orElse: () => years.first);
    final sections = await setup.loadSections();
    final section = sections.firstWhere((s) => s.academicYearId == year.id,
        orElse: () => sections.first);
    final subject = (await setup.loadSubjects()).first;

    // 1 · Exam
    final exam = await academics.createExam(
      campusId: campusId,
      academicYearId: year.id,
      name: 'E2E Exam $stamp',
      term: ExamTerm.firstTerm,
    );
    expect(exam.academicYearId, year.id,
        reason: 'the exam must store the year it was given');
    expect(exam.status, ExamStatus.pending);
    expect(exam.marksLocked, isFalse);

    final listed = await academics.loadExams(academicYearId: year.id);
    expect(listed.any((e) => e.id == exam.id), isTrue);

    // 2 · Paper — an exact maximum, carried as text the whole way
    final paper = await academics.createPaper(
      examId: exam.id,
      sectionId: section.id,
      subjectId: subject.id,
      maxMarks: Marks.parse('100'),
      passingMarks: Marks.parse('40'),
    );
    expect(paper.maxMarks, Marks.parse('100'));

    // 3 · The roster the marks screen loads
    final roster = await academics.loadRoster(section.id);
    expect(roster, isNotEmpty,
        reason: 'the section must have an enrolled student to mark');
    final student = roster.first;

    // 4 · One mark — and the result comes back computed
    final saved = await academics.saveMark(
      examSubjectId: paper.id,
      studentId: student.studentId,
      marksObtained: Marks.parse('85.50'),
    );
    expect(saved.error, isNull, reason: saved.error ?? '');
    final result = saved.result!;
    // The exact decimal survived the round trip. A double would have made
    // this 85.49999999999999.
    expect(result.totalMarks, Marks.parse('85.50'));
    expect(result.totalMarks.hundredths, 8550);
    expect(result.percentage, Marks.parse('85.50'));
    expect(result.grade, isNotEmpty,
        reason: 'a grade is assigned even though no scheme can be created');
    expect(result.status, ResultStatus.pass);

    // 5 · Over the maximum is refused, with a message worth showing
    final tooMuch = await academics.saveMark(
      examSubjectId: paper.id,
      studentId: student.studentId,
      marksObtained: Marks.parse('150'),
    );
    expect(tooMuch.result, isNull);
    expect(tooMuch.error, contains('exceeds max'));

    // 6 · A mark CAN be corrected before publishing
    final corrected = await academics.saveMark(
      examSubjectId: paper.id,
      studentId: student.studentId,
      marksObtained: Marks.parse('90'),
    );
    expect(corrected.error, isNull, reason: corrected.error ?? '');
    expect(corrected.result!.totalMarks, Marks.parse('90'));

    // 7 · The section's results, and the per-subject breakdown
    final sectionResults = await academics.loadSectionResults(
      examId: exam.id,
      sectionId: section.id,
    );
    expect(sectionResults.any((r) => r.studentId == student.studentId), isTrue);

    final studentResult = await academics.loadStudentResult(
      examId: exam.id,
      studentId: student.studentId,
    );
    expect(studentResult.subjects, isNotEmpty);
    expect(studentResult.totalMarks, Marks.parse('90'));

    // 8 · No report card before publishing — that is "not ready", not an error
    expect(
      await academics.loadReportCard(
          examId: exam.id, studentId: student.studentId),
      isNull,
    );

    // 9 · Publish — results and report cards appear together
    final published = await academics.publish(exam.id);
    expect(published.error, isNull, reason: published.error ?? '');
    expect(published.result!.resultsPublished, greaterThan(0));
    expect(published.result!.reportCardsGenerated, greaterThan(0));

    final card = await academics.loadReportCard(
      examId: exam.id,
      studentId: student.studentId,
    );
    expect(card, isNotNull);
    expect(card!.available, isTrue);

    // 10 · 🔴 And now the marks are locked, permanently
    final afterPublish = await academics.saveMark(
      examSubjectId: paper.id,
      studentId: student.studentId,
      marksObtained: Marks.parse('50'),
    );
    expect(afterPublish.result, isNull);
    expect(afterPublish.error, contains('locked'));

    // 11 · Syllabus — a chapter, a topic, coverage, and the SERVER's progress
    final chapter = await academics.createChapter(
      subjectId: subject.id,
      classId: section.classId,
      academicYearId: year.id,
      name: 'E2E Chapter $stamp',
      sortOrder: 99,
    );
    final topic = await academics.createTopic(
      chapterId: chapter.id,
      name: 'E2E Topic $stamp',
      sortOrder: 1,
    );

    expect(
      await academics.markCoverage(
        topicId: topic.id,
        sectionId: section.id,
        status: CoverageStatus.covered,
      ),
      isNull,
    );
    // Re-marking updates rather than conflicting — the unique constraint
    // behaves as an upsert.
    expect(
      await academics.markCoverage(
        topicId: topic.id,
        sectionId: section.id,
        status: CoverageStatus.covered,
      ),
      isNull,
    );

    final progress = await academics.loadProgress(
      subjectId: subject.id,
      classId: section.classId,
      sectionId: section.id,
      academicYearId: year.id,
    );
    expect(progress.totalTopics, greaterThan(0));
    expect(progress.coveredTopics, greaterThan(0));

    // 12 · A remark, and the one thing in this batch that can be undone
    final remark = await academics.createRemark(
      studentId: student.studentId,
      sectionId: section.id,
      remarkType: 'general',
      body: 'E2E remark $stamp',
      isParentVisible: false,
    );
    expect(remark.isParentVisible, isFalse);
    expect(
      (await academics.loadSectionRemarks(section.id))
          .any((r) => r.id == remark.id),
      isTrue,
    );

    await academics.deleteRemark(remark.id);
    expect(
      (await academics.loadSectionRemarks(section.id))
          .any((r) => r.id == remark.id),
      isFalse,
      reason: 'remarks are the one thing here that can be corrected',
    );
  });
}

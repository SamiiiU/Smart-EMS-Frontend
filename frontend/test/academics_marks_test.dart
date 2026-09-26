import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/academics/domain/academic_models.dart';
import 'package:smartems/features/academics/domain/marks.dart';

/// The numeric gate for T15.
///
/// Marks are not money, but a mark that renders as `17.999999` on a report
/// card is the same class of defect as a rupee of drift in a ledger: the
/// number looks authoritative and is wrong, and nobody can tell which of two
/// figures to believe.
void main() {
  group('no mark ever passes through a double', () {
    test('marks.dart mentions no floating-point type at all', () {
      final source =
          File('lib/features/academics/domain/marks.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('///') && !trimmed.startsWith('//');
          })
          .join('\n');

      for (final banned in ['double', 'toDouble', 'num ', 'parseDouble']) {
        expect(
          code.contains(banned),
          isFalse,
          reason: 'marks.dart contains "$banned". Marks are integer '
              'hundredths; one double here reintroduces the drift the type '
              'exists to prevent.',
        );
      }
    });

    test('a mark arriving as a NUMBER is rejected, not coerced', () {
      expect(() => Marks.fromJson(85.50), throwsA(isA<FormatException>()));
      expect(() => Marks.fromJson(85), throwsA(isA<FormatException>()));
    });

    test('the decoder hands marks to the app as text', () {
      const raw = '{"total_marks":85.50,"percentage":62.25,"grade":"B"}';
      final decoded =
          jsonDecode(AcademicJson.quoteNumbers(raw)) as Map<String, dynamic>;

      expect(decoded['total_marks'], '85.50');
      expect(decoded['percentage'], '62.25');
      expect(decoded['grade'], 'B');
    });

    test('a third decimal is refused', () {
      expect(Marks.tryParse('17.999'), isNull);
      expect(Marks.tryParse('17.99'), isNotNull);
      expect(Marks.tryParse('abc'), isNull);
    });

    test('marks add exactly', () {
      var total = Marks.zero;
      for (var i = 0; i < 3; i++) {
        total = total + Marks.parse('0.1');
      }
      expect(total, Marks.parse('0.3'));
      expect(0.1 + 0.1 + 0.1 == 0.3, isFalse);
    });
  });

  group('formatting — a mark is not a currency', () {
    test('trailing zeros are dropped, because 85.00 is noise on a report', () {
      expect(Marks.parse('85.00').format(), '85');
      expect(Marks.parse('85.50').format(), '85.5');
      expect(Marks.parse('85.25').format(), '85.25');
      expect(Marks.parse('100.00').format(), '100');
    });

    test('percentages carry their sign', () {
      expect(Marks.parse('62.50').formatPercent(), '62.5%');
      expect(Marks.parse('100.00').formatPercent(), '100%');
    });

    test('what goes back to the backend always has two decimals', () {
      expect(Marks.parse('85').toBackendString(), '85.00');
      expect(Marks.parse('85.5').toBackendString(), '85.50');
    });
  });

  group('no result is computed client-side', () {
    test('a result reports the server’s totals, not the sum of its subjects',
        () {
      // Subjects add to 150/200, but the server says 120/200 — a weighting
      // or a dropped paper the app knows nothing about. The server wins.
      final result = StudentResult.fromJson({
        'student_id': 's1',
        'student_name': 'Ali Khan',
        'total_marks': '120.00',
        'total_max': '200.00',
        'percentage': '60.00',
        'grade': 'C',
        'grade_point': '2.00',
        'position': 3,
        'result_status': 'pass',
        'subjects': [
          {
            'subject_name': 'Maths',
            'max_marks': '100.00',
            'passing_marks': '40.00',
            'marks_obtained': '80.00',
            'is_absent': false,
            'grade': 'A',
          },
          {
            'subject_name': 'Science',
            'max_marks': '100.00',
            'passing_marks': '40.00',
            'marks_obtained': '70.00',
            'is_absent': false,
            'grade': 'B',
          },
        ],
      });

      expect(result.totalMarks, Marks.parse('120.00'));
      expect(result.totalMarks, isNot(Marks.parse('150.00')),
          reason: 'the subject sum must never win over the server total');
      expect(result.percentage, Marks.parse('60.00'));
      expect(result.grade, 'C');
      expect(result.gradePoint, Marks.parse('2.00'));
      expect(result.position, 3);
    });

    test('syllabus progress is the server’s percentage, not covered ÷ total',
        () {
      // 1 of 3 is 33.33…%, and the server says 40 — it counts partials
      // differently. Rendering our own division would contradict it.
      final progress = SyllabusProgress.fromJson({
        'percentage': '40.00',
        'coveredTopics': 1,
        'totalTopics': 3,
        'coveredChapters': 0,
        'totalChapters': 1,
        'chapters': const [],
      });

      expect(progress.percentage, Marks.parse('40.00'));
      expect(progress.percentage.formatPercent(), '40%');
    });
  });

  group('grade bands — gaps and overlaps are rejected', () {
    GradeBand band(String min, String max, String grade) => GradeBand(
          minPercent: Marks.parse(min),
          maxPercent: Marks.parse(max),
          grade: grade,
          gradePoint: Marks.parse('4.00'),
        );

    test('a complete set of bands is accepted', () {
      expect(
        validateBands([
          band('0', '39.99', 'F'),
          band('40', '59.99', 'C'),
          band('60', '79.99', 'B'),
          band('80', '100', 'A'),
        ]),
        isNull,
      );
    });

    test('a GAP is rejected, and says what a student in it would get', () {
      // Nothing covers 60.00–69.99.
      final problem = validateBands([
        band('0', '59.99', 'C'),
        band('70', '100', 'A'),
      ]);
      expect(problem, isNotNull);
      expect(problem, contains('no grade'));
    });

    test('an OVERLAP is rejected', () {
      final problem = validateBands([
        band('0', '60', 'C'),
        band('55', '100', 'A'),
      ]);
      expect(problem, isNotNull);
      expect(problem, contains('overlap'));
    });

    test('bands that do not reach 0 or 100 are rejected', () {
      expect(validateBands([band('10', '100', 'A')]), contains('start at 0'));
      expect(validateBands([band('0', '90', 'A')]), contains('end at 100'));
    });

    test('a band that starts above where it ends is rejected', () {
      expect(
        validateBands([band('80', '40', 'A')]),
        contains('starts above where it ends'),
      );
    });

    test('no bands at all is rejected', () {
      expect(validateBands(const []), isNotNull);
    });
  });

  group('results are ordered by who needs attention (D-15)', () {
    StudentResult r(String name, String percent, String status) =>
        StudentResult.fromJson({
          'student_id': name,
          'student_name': name,
          'total_marks': percent,
          'total_max': '100.00',
          'percentage': percent,
          'grade': 'X',
          'grade_point': '1.00',
          'result_status': status,
        });

    test('failures first, then borderline passes, then everyone else', () {
      final sorted = sortResults([
        r('Top', '95.00', 'pass'),
        r('Borderline', '45.00', 'pass'),
        r('Failed', '20.00', 'fail'),
        r('Comfortable', '75.00', 'pass'),
      ]);

      expect(
        sorted.map((x) => x.studentName),
        ['Failed', 'Borderline', 'Comfortable', 'Top'],
      );
    });

    test('a borderline pass is a display hint, never a status', () {
      expect(r('A', '45.00', 'pass').isBorderline, isTrue);
      expect(r('B', '55.00', 'pass').isBorderline, isFalse);
      // A failure is never ALSO borderline — it is already at the top.
      expect(r('C', '20.00', 'fail').isBorderline, isFalse);
    });
  });

  group('a mark entry validates as it is typed', () {
    const max = Marks.fromHundredths(10000); // 100

    MarkEntry entry(String text, {bool absent = false}) => MarkEntry(
          studentId: 's',
          studentName: 'Ali',
          text: text,
          isAbsent: absent,
        );

    test('over the maximum is caught with the maximum named', () {
      expect(entry('150').problem(max), 'Over 100');
    });

    test('a non-number is caught', () {
      expect(entry('abc').problem(max), 'Not a number');
    });

    test('a negative is caught', () {
      expect(entry('-5').problem(max), 'Cannot be negative');
    });

    test('empty is not a problem — it is just not entered yet', () {
      expect(entry('').problem(max), isNull);
      expect(entry('').isEntered, isFalse);
    });

    test('absent counts as entered and carries no number', () {
      final absent = entry('', absent: true);
      expect(absent.isEntered, isTrue);
      expect(absent.problem(max), isNull);
      expect(absent.value, isNull);
    });

    test('a valid mark is entered and has no problem', () {
      expect(entry('85.5').problem(max), isNull);
      expect(entry('85.5').isEntered, isTrue);
      expect(entry('85.5').value, Marks.parse('85.5'));
    });
  });

  group('exam vocabulary', () {
    test('only the six terms the backend accepts exist', () {
      expect(
        ExamTerm.values.map((t) => t.wire),
        ['weekly', 'monthly', 'first_term', 'mid_term', 'final', 'annual'],
      );
    });

    test('publishing is what locks the marks', () {
      Exam exam(String status) => Exam.fromJson({
            'id': 'e',
            'name': 'Term 1',
            'status': status,
            'academic_year_id': 'y',
          });

      expect(exam('pending').marksLocked, isFalse);
      expect(exam('published').marksLocked, isTrue);
    });

    test('only the two coverage statuses the backend accepts exist', () {
      expect(CoverageStatus.values.map((s) => s.wire), ['covered', 'partial']);
    });
  });
}

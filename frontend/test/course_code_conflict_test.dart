import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/academy/presentation/courses_screen.dart';

void main() {
  test('generic unique-violation on course create names the duplicate code', () {
    expect(courseCodeConflict('Conflicts with existing data', ' math-11 '),
        'A course with code "math-11" already exists (codes are not case-sensitive). Use a different code.');
  });
  test('other messages and success pass through unchanged', () {
    expect(courseCodeConflict(null, 'X'), isNull);
    expect(courseCodeConflict('Academy courses and batches are not enabled for this institution.', 'X'),
        'Academy courses and batches are not enabled for this institution.');
  });
}

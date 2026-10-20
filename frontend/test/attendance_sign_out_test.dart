import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:drift/native.dart';
import 'package:smartems/features/attendance/data/attendance_queue.dart';
import 'package:smartems/features/attendance/domain/attendance_models.dart';
import 'package:smartems/features/attendance/presentation/attendance_sign_out.dart';

class UnreadableQueue extends AttendanceQueue {
  UnreadableQueue(super.executor);
  bool removed = false;
  @override
  Future<List<AttendanceMark>> pending() async =>
      throw StateError('Synthetic decryption failure');
  @override
  Future<void> remove(Iterable<String> ids) async {
    removed = true;
  }
}

void main() {
  testWidgets(
    'unreadable vault can sign out only while retaining stored data',
    (tester) async {
      final db = NativeDatabase.memory();
      final queue = UnreadableQueue(db);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmAttendanceSignOut(context, queue);
              },
              child: const Text('Start'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Saved attendance unavailable'), findsOneWidget);
      expect(find.text('Discard marks'), findsNothing);
      await tester.tap(find.text('Keep data and sign out'));
      await tester.pumpAndSettle();
      expect(result, true);
      expect(queue.removed, false);
      await db.close();
    },
  );
  for (final choice in ['Cancel', 'Keep and sign out', 'Discard marks']) {
    testWidgets('pending attendance sign-out: $choice', (tester) async {
      final db = NativeDatabase.memory();
      final queue = AttendanceQueue(db);
      await queue.enqueue([
        const AttendanceMark(
          clientUuid: 'id',
          sectionId: 's',
          studentId: 'p',
          attendanceDate: '2026-10-13',
          status: AttendanceStatus.present,
        ),
      ]);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmAttendanceSignOut(context, queue);
              },
              child: const Text('Start'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 attendance marks'), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      if (choice == 'Discard marks') {
        expect(await queue.pendingCount(), 1);
        expect(find.text('Discard unsynced marks?'), findsOneWidget);
        await tester.tap(find.text('Discard and sign out'));
        await tester.pumpAndSettle();
        expect(result, true);
        expect(await queue.pendingCount(), 0);
      } else {
        expect(result, choice == 'Keep and sign out');
        expect(await queue.pendingCount(), 1);
      }
      await db.close();
    });
  }
}

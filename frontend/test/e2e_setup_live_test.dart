import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';

/// T13 Batch A's end-to-end proof, against the REAL backend.
///
/// Onboards a school the way the screens do — academic year → class →
/// section → subject → teaching assignment → one timetable slot — using
/// `SetupRepository`, which is the exact code path every setup screen goes
/// through. No curl, and no hand-written request bodies.
///
/// Run it with the backend up:
/// ```
/// flutter test test/e2e_setup_live_test.dart --dart-define=LIVE=true
/// ```
/// Without the flag it skips itself, and it skips again if the backend is
/// not answering, so the ordinary suite stays hermetic and can never go red
/// because a server is down.
///
/// 🔴 **Why this drives the repository and not the widgets.** `flutter
/// test` replaces the clock with a fake one, and a real HTTP call started
/// by a widget never completes inside it — the screen sits on "Saving…"
/// for ever. Only work wrapped in `runAsync` reaches the real event loop,
/// and a widget's own `initState` load cannot be. Driving the actual
/// widgets against a live server needs `integration_test` on a device or
/// browser, which this project does not have set up (and on web the port
/// would have to be the CORS-allowlisted 3000). So:
///   - the screens' behaviour is covered hermetically in `setup_test.dart`
///     against a stub that encodes this backend's real quirks;
///   - the network path is covered here, live;
///   - the two meeting in a browser is the manual check in HANDOFF.md.
/// Stated rather than papered over: this is NOT the full "no terminal"
/// proof on its own.
///
/// Cleans up what this backend allows (slot, section, class, subject,
/// year). A teaching assignment cannot be deleted — no endpoint exists —
/// so one row per run is left in `test-school`.
const _base = 'http://localhost:8080';

const bool _enabled = bool.fromEnvironment('LIVE');

Future<bool> _backendUp() async {
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
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
  test('a school is onboarded end to end, through the app’s own code',
      () async {
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

    final setup = SetupRepository(dio);
    final admin = AdminRepository(dio);

    final campusId = (await admin.loadCampusIds()).first;
    final stamp =
        DateTime.now().millisecondsSinceEpoch.toString().substring(8);

    // 1 · Academic year
    final year = await setup.createYear(
      campusId: campusId,
      name: 'E2E $stamp',
      startDate: '2030-08-01',
      endDate: '2031-05-31',
    );
    expect((await setup.loadYears()).any((y) => y.id == year.id), isTrue);
    // The flag the screen refuses to offer a control for.
    expect(year.current, isFalse,
        reason: 'a created year is never current on this backend');

    // 2 · Class
    final schoolClass = await setup.createClass(
      campusId: campusId,
      name: 'E2E Class $stamp',
      levelOrder: 11,
    );
    expect((await setup.loadClasses()).any((c) => c.id == schoolClass.id),
        isTrue);

    // 3 · Section — requires the year, which is why the order matters
    final section = await setup.createSection(
      classId: schoolClass.id,
      academicYearId: year.id,
      name: 'E2E-$stamp',
      capacity: 30,
    );
    expect(section.academicYearId, year.id);

    // 4 · Subject
    final subject = await setup.createSubject(
      name: 'E2E Subject $stamp',
      code: 'E2E$stamp',
    );

    // 5 · Teaching assignment
    final staff = (await admin.loadPeople()).staff;
    final teacher = staff.firstWhere((s) => s.fullName.contains('Ayesha'),
        orElse: () => staff.first);
    await setup.createAssignment(
      staffId: teacher.id,
      sectionId: section.id,
      subjectId: subject.id,
      academicYearId: year.id,
    );
    expect(await setup.loadAssignments(section.id), isNotEmpty);

    // 6 · One timetable slot, on a day the seeded teacher is free
    final periods = await setup.loadPeriods(campusId);
    expect(periods, isNotEmpty, reason: 'the school day has periods');
    final teaching = periods.firstWhere((p) => !p.isBreak);

    final (slot, failure) = await setup.createSlot(
      sectionId: section.id,
      academicYearId: year.id,
      periodId: teaching.id,
      dayOfWeek: 6, // Saturday — nothing is seeded there
      subjectId: subject.id,
      teacherStaffId: teacher.id,
    );
    expect(failure, isNull, reason: failure?.message ?? '');
    expect(slot, isNotNull);

    final week = await setup.loadWeek(
      sectionId: section.id,
      academicYearId: year.id,
    );
    expect(week.any((s) => s.dayOfWeek == 6), isTrue);

    // Cleanup
    for (final s in week) {
      await setup.deleteSlot(s.id);
    }
    await dio.delete<void>('/api/sections/${section.id}');
    await dio.delete<void>('/api/classes/${schoolClass.id}');
    await dio.delete<void>('/api/subjects/${subject.id}');
    await dio.delete<void>('/api/academic-years/${year.id}');
  });
}

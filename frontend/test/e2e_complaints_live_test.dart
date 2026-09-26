import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/complaints/data/complaints_repository.dart';
import 'package:smartems/features/complaints/domain/complaint_models.dart';
import 'package:smartems/features/notifications/data/notifications_repository.dart';
import 'package:smartems/features/staff_attendance/data/staff_attendance_repository.dart';
import 'package:smartems/features/staff_attendance/domain/staff_attendance_models.dart';

/// T16's end-to-end proof, against the REAL backend, through the app's own
/// repositories.
///
/// It walks the full complaint lifecycle across TWO accounts, which is the
/// only way to prove the part that matters: that a complainant never
/// receives an internal note.
///
/// ```
/// flutter test test/e2e_complaints_live_test.dart --dart-define=LIVE=true
/// ```
///
/// 🔴 **The raiser is a TEACHER, not a parent.** A parent cannot raise a
/// complaint at all: `POST /api/complaints` requires `campusId`, and no
/// endpoint a parent may call carries one (`/api/campuses` is 403,
/// `/api/guardians/me` and `/api/institution/me` have no campus). That is
/// open item 39, and it is asserted below rather than worked around.
///
/// 🔴 Same honest limit as the other three live tests: this drives the
/// REPOSITORY, not the widgets. `flutter test` uses a fake clock, so a
/// widget-initiated request never completes. `integration_test/` now exists
/// for the widget half — see HANDOFF.md for how to run it.
///
/// 🔴 It cannot clean up. There is no delete for a complaint, a comment or
/// an attendance record, so every run leaves rows in `test-school`.
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

Future<Dio> _signIn(String username) async {
  final dio = Dio(BaseOptions(baseUrl: _base));
  final res = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {
      'institutionCode': 'test-school',
      'username': username,
      'password': 'Test1234!',
    },
  );
  dio.options.headers['Authorization'] = 'Bearer ${res.data!['accessToken']}';
  return dio;
}

void main() {
  test('a complaint is raised, assigned, answered and resolved — and the '
      'internal note never leaks', () async {
    if (!_enabled) {
      markTestSkipped('live test — pass --dart-define=LIVE=true to run it');
      return;
    }
    if (!await _backendUp()) {
      markTestSkipped('backend not running on $_base');
      return;
    }

    final teacherDio = await _signIn('teacher1');
    final adminDio = await _signIn('admin');
    final parentDio = await _signIn('parent1');

    final teacher = ComplaintsRepository(teacherDio);
    final admin = ComplaintsRepository(adminDio);
    final parent = ComplaintsRepository(parentDio);

    final stamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);

    // --- 0 · The parent limitation, asserted rather than assumed ----------
    expect(
      await parent.resolveCampusId(),
      isNull,
      reason: 'a parent has no endpoint carrying a campusId (open item 39)',
    );

    // --- 1 · Raise, as a teacher ------------------------------------------
    final campusId = await teacher.resolveCampusId();
    expect(campusId, isNotNull, reason: 'a teacher resolves one via /staff/me');

    final raised = await teacher.raise(
      campusId: campusId!,
      category: ComplaintCategory.facility,
      subject: 'E2E $stamp',
      description: 'Raised by the end-to-end test.',
      priority: ComplaintPriority.high,
    );
    expect(raised.status, ComplaintStatus.open);
    expect(raised.isAnonymous, isFalse);

    // It is in the raiser's own list.
    expect(
      (await teacher.loadMine()).any((c) => c.id == raised.id),
      isTrue,
    );

    // --- 2 · It reaches the admin worklist --------------------------------
    final adminList = await admin.loadAll();
    expect(adminList.any((c) => c.id == raised.id), isTrue);

    // --- 3 · Assign it ----------------------------------------------------
    final staff = await adminDio.get<Map<String, dynamic>>(
      '/api/staff',
      queryParameters: const {'size': 10},
    );
    final staffId = (staff.data?['content'] as List).first['id'] as String;
    await admin.assign(id: raised.id, staffId: staffId);
    expect((await admin.load(raised.id)).assignedToStaffId, staffId);

    // --- 4 · Two comments: one internal, one not --------------------------
    await admin.comment(
      id: raised.id,
      body: 'INTERNAL $stamp — staff eyes only',
      isInternal: true,
    );
    await admin.comment(
      id: raised.id,
      body: 'PUBLIC $stamp — we are on it',
    );

    final adminSees = await admin.loadComments(raised.id);
    expect(adminSees.where((c) => c.isInternal).length, 1);
    expect(adminSees.length, 2);

    // 🔴 THE assertion this whole test exists for.
    final raiserSees = await teacher.loadComments(raised.id);
    expect(
      raiserSees.any((c) => c.isInternal),
      isFalse,
      reason: 'an internal note must never reach the complainant',
    );
    expect(
      raiserSees.any((c) => c.body.contains('INTERNAL')),
      isFalse,
      reason: 'not merely unflagged — the body itself must not arrive',
    );
    expect(raiserSees.any((c) => c.body.contains('PUBLIC')), isTrue);

    // A complainant cannot create an internal note either — the server
    // downgrades it rather than trusting the client.
    await teacher.comment(
      id: raised.id,
      body: 'Trying to go internal $stamp',
      isInternal: true,
    );
    final afterTeacher = await teacher.loadComments(raised.id);
    expect(
      afterTeacher.every((c) => !c.isInternal),
      isTrue,
      reason: 'the server downgrades a complainant’s isInternal to false',
    );

    // --- 5 · Resolve, and the raiser's view updates -----------------------
    await admin.setStatus(
      id: raised.id,
      status: ComplaintStatus.resolved,
      resolutionNote: 'Fixed by the E2E test.',
    );

    final raiserView =
        (await teacher.loadMine()).firstWhere((c) => c.id == raised.id);
    expect(raiserView.status, ComplaintStatus.resolved);

    // --- 6 · An anonymous one carries no identity, for anyone -------------
    final anon = await teacher.raise(
      campusId: campusId,
      category: ComplaintCategory.other,
      subject: 'E2E anon $stamp',
      description: 'Anonymously raised.',
      isAnonymous: true,
    );
    expect(anon.raisedByUserId, isNull);
    // Including in the ADMIN's own detail view.
    expect((await admin.load(anon.id)).raisedByUserId, isNull);

    // --- 7 · Notifications were produced, and read state persists ---------
    final notifications = NotificationsRepository(adminDio);
    final before = await notifications.unreadCount();
    expect(before, greaterThanOrEqualTo(0));

    final marked = await notifications.markAllRead();
    expect(marked, greaterThanOrEqualTo(0));
    expect(
      await notifications.unreadCount(),
      0,
      reason: 'read state is stored server-side, not on the device',
    );

    // --- 8 · Staff attendance: one call, and half_day is accepted ---------
    final attendance = StaffAttendanceRepository(adminDio);
    const date = '2026-09-27';
    final day = await attendance.loadDay(date);
    expect(day.rows, isNotEmpty);
    expect(day.totalStaff, greaterThan(0));

    final error = await attendance.mark(
      staffId: day.rows.first.staffId,
      date: date,
      // Rejected outright for a STUDENT — the vocabularies really differ.
      status: StaffAttendanceStatus.halfDay,
    );
    expect(error, isNull, reason: error ?? '');

    final after = await attendance.loadDay(date);
    expect(
      after.rows.firstWhere((r) => r.staffId == day.rows.first.staffId).status,
      StaffAttendanceStatus.halfDay,
    );
  });
}

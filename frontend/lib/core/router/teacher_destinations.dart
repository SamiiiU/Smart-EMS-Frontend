import 'package:flutter/material.dart';

import '../../features/attendance/data/attendance_repository.dart';
import '../../features/complaints/data/complaints_repository.dart';
import '../../features/complaints/presentation/my_complaints_screen.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/attendance/presentation/attendance_marking_screen.dart';
import '../../features/diary/data/diary_repository.dart';
import '../../features/diary/domain/diary_models.dart';
import '../../features/diary/presentation/diary_editor_screen.dart';
import '../../features/parent/data/parent_repository.dart';
import '../../features/parent/presentation/parent_home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../theme/theme_controller.dart';
import '../../features/student/presentation/student_timetable_unavailable.dart';
import '../../features/timetable/data/timetable_repository.dart';
import '../../features/timetable/presentation/today_screen.dart';
import '../shell/nav_destination.dart';

/// Destinations wired to REAL screens.
///
/// `RoleDestinations` holds the ordered priority list as pure data (D-31),
/// which is right for the list itself but cannot build screens — those need
/// repositories. This assembles the same ordering with live builders, and is
/// the only place that knows both.
///
/// Only the destinations T8 actually built are real; the rest keep their
/// placeholder so the nav is honest about what exists.
List<NavDestination> buildTeacherDestinations({
  required AttendanceRepository attendance,
  required TimetableRepository timetable,
  required String? staffId,
  required Future<void> Function() onSignOut,
  required String? institutionCode,
  ThemeController? themeController,
  DiaryRepository? diary,
  String? staffName,
  ComplaintsRepository? complaints,
  NotificationsRepository? notifications,
}) {
  return [
    NavDestination(
      id: 'today',
      label: 'Today',
      icon: Icons.today_outlined,
      route: '/today',
      builder: (context) => _TodayFlow(
        timetable: timetable,
        attendance: attendance,
        staffId: staffId,
      ),
    ),
    NavDestination(
      id: 'diary',
      label: 'Diary',
      icon: Icons.menu_book_outlined,
      route: '/diary',
      // Null only in tests that do not wire the diary.
      builder: (context) => diary == null
          ? const _NotBuiltYet(label: 'Diary')
          : _DiaryFlow(
              timetable: timetable,
              diary: diary,
              staffId: staffId,
              staffName: staffName,
            ),
    ),
    // T16. Optional so the many tests that build these lists without a
    // network layer keep working — a null repository means the
    // destination simply is not offered, rather than a tab that throws.
    if (notifications != null)
      NavDestination(
        id: 'notifications',
        label: 'Notifications',
        icon: Icons.notifications_none,
        route: '/notifications',
        builder: (context) => NotificationsScreen(repository: notifications),
      ),
    if (complaints != null)
      NavDestination(
        id: 'complaints',
        label: 'Complaints',
        icon: Icons.forum_outlined,
        route: '/complaints',
        builder: (context) => MyComplaintsScreen(repository: complaints),
      ),
    NavDestination(
      id: 'more',
      label: 'More',
      icon: Icons.more_horiz,
      route: '/more',
      alwaysVisible: true,
      builder: (context) => SettingsScreen(
        onSignOut: onSignOut,
        institutionCode: institutionCode,
        themeController: themeController,
      ),
    ),
  ];
}

/// Parent destinations, wired to real screens.
///
/// Reuses the SAME `SettingsScreen` as the teacher list — sign-out is
/// sign-out, and a second copy would be two places to fix the next time it
/// changes. Fees are deliberately absent: a paid add-on under D-31's
/// entitlement model, not Foundation.
List<NavDestination> buildParentDestinations({
  required ParentRepository parent,
  required Future<void> Function() onSignOut,
  required String? institutionCode,
  ThemeController? themeController,
  ComplaintsRepository? complaints,
  NotificationsRepository? notifications,
}) {
  return [
    NavDestination(
      id: 'my_child',
      label: 'My child',
      icon: Icons.child_care_outlined,
      route: '/my-child',
      builder: (context) => ParentHomeScreen(repository: parent),
    ),
    // T16. Optional so the many tests that build these lists without a
    // network layer keep working — a null repository means the
    // destination simply is not offered, rather than a tab that throws.
    if (notifications != null)
      NavDestination(
        id: 'notifications',
        label: 'Notifications',
        icon: Icons.notifications_none,
        route: '/notifications',
        builder: (context) => NotificationsScreen(repository: notifications),
      ),
    if (complaints != null)
      NavDestination(
        id: 'complaints',
        label: 'Complaints',
        icon: Icons.forum_outlined,
        route: '/complaints',
        builder: (context) => MyComplaintsScreen(repository: complaints),
      ),
    NavDestination(
      id: 'more',
      label: 'More',
      icon: Icons.more_horiz,
      route: '/more',
      alwaysVisible: true,
      builder: (context) => SettingsScreen(
        onSignOut: onSignOut,
        institutionCode: institutionCode,
        themeController: themeController,
      ),
    ),
  ];
}

/// Student destinations (T11).
///
/// Today and Timetable are wired to an honest "not available yet" state, not
/// to the real screens: a student cannot yet discover their own section from
/// the API (see `StudentTimetableUnavailable`). Before this existed a student
/// login fell through to the TEACHER list — Today would have asked for a
/// staff record the student does not have.
List<NavDestination> buildStudentDestinations({
  required Future<void> Function() onSignOut,
  required String? institutionCode,
  ThemeController? themeController,
  ComplaintsRepository? complaints,
  NotificationsRepository? notifications,
}) {
  return [
    NavDestination(
      id: 'today',
      label: 'Today',
      icon: Icons.today_outlined,
      route: '/today',
      builder: (context) => const StudentTimetableUnavailable(title: 'Today'),
    ),
    NavDestination(
      id: 'timetable',
      label: 'Timetable',
      icon: Icons.schedule_outlined,
      route: '/timetable',
      builder: (context) =>
          const StudentTimetableUnavailable(title: 'Timetable'),
    ),
    // T16. Optional so the many tests that build these lists without a
    // network layer keep working — a null repository means the
    // destination simply is not offered, rather than a tab that throws.
    if (notifications != null)
      NavDestination(
        id: 'notifications',
        label: 'Notifications',
        icon: Icons.notifications_none,
        route: '/notifications',
        builder: (context) => NotificationsScreen(repository: notifications),
      ),
    if (complaints != null)
      NavDestination(
        id: 'complaints',
        label: 'Complaints',
        icon: Icons.forum_outlined,
        route: '/complaints',
        builder: (context) => MyComplaintsScreen(repository: complaints),
      ),
    NavDestination(
      id: 'more',
      label: 'More',
      icon: Icons.more_horiz,
      route: '/more',
      alwaysVisible: true,
      builder: (context) => SettingsScreen(
        onSignOut: onSignOut,
        institutionCode: institutionCode,
        themeController: themeController,
      ),
    ),
  ];
}

/// Today → marking screen.
///
/// A local two-step rather than a nested route, so the tab keeps its own
/// state (D-30) and back returns to the period list rather than leaving the
/// tab. This replaces T8's interim section picker, which existed only
/// because Today could not supply a sectionId.
class _TodayFlow extends StatefulWidget {
  const _TodayFlow({
    required this.timetable,
    required this.attendance,
    required this.staffId,
  });

  final TimetableRepository timetable;
  final AttendanceRepository attendance;
  final String? staffId;

  @override
  State<_TodayFlow> createState() => _TodayFlowState();
}

class _TodayFlowState extends State<_TodayFlow> {
  TimetablePeriod? _period;

  @override
  Widget build(BuildContext context) {
    final period = _period;
    if (period == null) {
      return TodayScreen(
        repository: widget.timetable,
        staffId: widget.staffId,
        onOpenRegister: (p) => setState(() => _period = p),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _period = null);
      },
      child: AttendanceMarkingScreen(
        repository: widget.attendance,
        // Non-null: TodayScreen only offers a tap when sectionId exists.
        sectionId: period.sectionId!,
        sectionLabel: period.sectionName ?? 'Register',
        attendanceDate: DateTime.now(),
      ),
    );
  }
}

/// Diary tab: today's periods → that period's diary.
///
/// The same period list as Today (reused, not copied), because the diary is
/// keyed by section + subject and the period already carries both — asking
/// the teacher to pick them again would be the wrong design and a chance to
/// pick the wrong class. A period without a section or subject stays inert
/// (TodayScreen already makes section-less rows non-tappable).
class _DiaryFlow extends StatefulWidget {
  const _DiaryFlow({
    required this.timetable,
    required this.diary,
    required this.staffId,
    required this.staffName,
  });

  final TimetableRepository timetable;
  final DiaryRepository diary;
  final String? staffId;
  final String? staffName;

  @override
  State<_DiaryFlow> createState() => _DiaryFlowState();
}

class _DiaryFlowState extends State<_DiaryFlow> {
  TimetablePeriod? _period;

  @override
  Widget build(BuildContext context) {
    final period = _period;
    if (period == null) {
      return TodayScreen(
        title: 'Diary',
        repository: widget.timetable,
        staffId: widget.staffId,
        onOpenRegister: (p) => setState(() => _period = p),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _period = null);
      },
      child: DiaryEditorScreen(
        repository: widget.diary,
        diaryKey: DiaryKey(
          // Non-null: TodayScreen only offers a tap when sectionId exists.
          sectionId: period.sectionId!,
          subjectId: period.subjectId,
          date: DateTime.now(),
        ),
        heading: period.sectionName ?? 'Diary',
        subjectLabel: period.subjectName,
        currentTeacherName: widget.staffName,
      ),
    );
  }
}

class _NotBuiltYet extends StatelessWidget {
  const _NotBuiltYet({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('$label — built in a later task'));
  }
}

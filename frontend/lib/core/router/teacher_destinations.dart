import '../../features/academics/data/academics_repository.dart';
import '../../features/academics/data/subject_resources_repository.dart';
import '../../features/academics/presentation/learner_resources_screen.dart';
import '../../features/academics/presentation/subject_resources_screen.dart';
import '../../features/academics/presentation/teacher_marks_flow.dart';
import '../../features/academics/presentation/teacher_syllabus_flow.dart';
import '../../features/academy/data/academy_repository.dart';
import '../../features/academy/presentation/academy_today_panel.dart';
import 'package:flutter/material.dart';

import '../../features/attendance/data/attendance_repository.dart';
import '../../features/complaints/data/complaints_repository.dart';
import '../../features/complaints/presentation/my_complaints_screen.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/attendance/presentation/attendance_marking_screen.dart';
import '../../features/attendance/presentation/my_registers_panel.dart';
import '../../features/diary/data/diary_repository.dart';
import '../../features/diary/domain/diary_models.dart';
import '../../features/diary/presentation/diary_editor_screen.dart';
import '../../features/parent/data/parent_repository.dart';
import '../../features/parent/presentation/parent_home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../theme/theme_controller.dart';
import '../../features/student/presentation/student_timetable_unavailable.dart';
import '../../features/student/presentation/student_timetable_screen.dart';
import '../../features/student/presentation/student_today_screen.dart';
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
  // ACADEMY profile only: Today also lists the teacher's dated course
  // sessions (report 11 A-2). [campusChanges] reloads them on a campus switch.
  AcademyRepository? academy,
  AcademicsRepository? academics,
  Listenable? campusChanges,
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
        academy: academy,
        campusChanges: campusChanges,
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
    // Owner decision (18 Oct 2026): teachers reach Syllabus and coverage for
    // their own assigned sections/subjects. School/College only — the Academy
    // profile has no School syllabus. Null in tests that do not wire it.
    if (academics != null && academy == null)
      NavDestination(
        id: 'syllabus',
        label: 'Syllabus',
        icon: Icons.library_books_outlined,
        route: '/syllabus',
        builder: (context) =>
            TeacherSyllabusFlow(repository: academics, staffId: staffId),
      ),
    // OBS-06 (owner-approved route), served by D-13: the teacher's own exam
    // papers → Marks Entry. School/College only.
    if (academics != null && academy == null)
      NavDestination(
        id: 'marks',
        label: 'Marks',
        icon: Icons.edit_note_outlined,
        route: '/marks',
        builder: (context) => TeacherMarksFlow(repository: academics),
      ),
    // D-21: the teacher's assigned subjects/classes → subject resources.
    // School/College only (the approved scope).
    if (academics != null && academy == null)
      NavDestination(
        id: 'resources',
        label: 'Resources',
        icon: Icons.folder_outlined,
        route: '/resources',
        builder: (context) =>
            TeacherResourcesFlow(academics: academics, staffId: staffId),
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
  // Only for an ACADEMY-profile institution (Academy-only children, report 11 A-1).
  AcademyRepository? academy,
}) {
  return [
    NavDestination(
      id: 'my_child',
      label: 'My child',
      icon: Icons.child_care_outlined,
      route: '/my-child',
      builder: (context) =>
          ParentHomeScreen(repository: parent, academy: academy),
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
  ParentRepository? parent,
  AcademyRepository? academy,
}) {
  return [
    NavDestination(
      id: 'today',
      label: 'Today',
      icon: Icons.today_outlined,
      route: '/today',
      // Real Today from the student's own progress (approved reads). Without
      // a repository (tests that build lists offline) the honest placeholder.
      builder: (context) => parent == null
          ? const StudentTimetableUnavailable(title: 'Today')
          : StudentTodayScreen(repository: parent, academy: academy),
    ),
    NavDestination(
      id: 'timetable',
      label: 'Timetable',
      icon: Icons.schedule_outlined,
      route: '/timetable',
      // D-19: shows the real week once the proposed self-enrollment read
      // exists; until then (or offline in tests) the honest placeholder.
      builder: (context) => parent == null
          ? const StudentTimetableUnavailable(title: 'Timetable')
          : StudentTimetableScreen(
              repository: parent,
              academyInstitution: academy != null,
            ),
    ),
    // D-21: read-only resources of the student's own current class.
    // School/College only (the approved scope).
    if (parent != null && academy == null)
      NavDestination(
        id: 'resources',
        label: 'Resources',
        icon: Icons.folder_outlined,
        route: '/resources',
        builder: (context) => StudentResourcesFlow(
          parent: parent,
          repository: SubjectResourcesRepository(parent.dio),
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
    this.academy,
    this.campusChanges,
  });

  final TimetableRepository timetable;
  final AttendanceRepository attendance;
  final String? staffId;
  final AcademyRepository? academy;
  final Listenable? campusChanges;

  @override
  State<_TodayFlow> createState() => _TodayFlowState();
}

class _TodayFlowState extends State<_TodayFlow> {
  /// The register being shown: from a timetabled period OR from "Your
  /// classes" (BUG-QA-11), so attendance never depends on a timetable.
  ({String sectionId, String label})? _open;

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open == null) {
      return TodayScreen(
        repository: widget.timetable,
        staffId: widget.staffId,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.academy case final academy?)
              AcademyTodayPanel(
                repository: academy,
                campusChanges: widget.campusChanges,
              ),
            MyRegistersPanel(
              repository: widget.attendance,
              onOpen: (r) => setState(
                () => _open = (sectionId: r.sectionId, label: r.label),
              ),
            ),
          ],
        ),
        // Non-null sectionId: TodayScreen only offers a tap when it exists.
        onOpenRegister: (p) => setState(
          () => _open = (
            sectionId: p.sectionId!,
            label: p.sectionName ?? 'Register',
          ),
        ),
      );
    }
    // The register owns back handling (unsaved-changes guard); it calls
    // onExit only when leaving is allowed (NOTE-QA-17).
    return KeyedSubtree(
      child: AttendanceMarkingScreen(
        onExit: () => setState(() => _open = null),
        repository: widget.attendance,
        sectionId: open.sectionId,
        sectionLabel: open.label,
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

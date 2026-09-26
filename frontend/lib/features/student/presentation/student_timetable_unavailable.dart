import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states/empty_state.dart';

/// Student Today / Timetable, while the backend cannot tell a student which
/// section they are in.
///
/// **Why this exists instead of the real screen (T11, 2026-09-18).** The only
/// timetable a student may read is `/api/timetable/section/{sectionId}`, and
/// no endpoint a student can call yields their own `sectionId`:
/// `/api/students/me` has no enrollment field, `/api/enrollments/student/{id}`
/// is 403, and `parent-progress` carries the section NAME only. Matching a
/// name against the section list would be a guess (section names are not
/// unique — T8), and building on mock data would mean writing code against a
/// shape nobody has verified. So neither is done.
///
/// Same pattern as `UnlinkedProfileState` — informational, no retry, because
/// the student cannot fix it — but a DIFFERENT message: this is not an
/// orphan login. The student is linked correctly; a backend field is missing.
/// Requested from Ali (see BACKEND_CONTRACT.md → T11 open items). When
/// `sectionId` lands on `/api/students/me`, this is replaced by the real
/// screen in a small follow-up, not a reopened T11.
class StudentTimetableUnavailable extends StatelessWidget {
  const StudentTimetableUnavailable({required this.title, super.key});

  /// The tab's own name ("Today" / "Timetable").
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: StateFrame(
          icon: Icons.schedule_outlined,
          iconColour: t.info,
          title: '$title is not available yet',
          message: 'Your timetable cannot be shown in the app yet. This is '
              'being added by the school’s system — nothing is wrong with '
              'your account. For today’s classes, please check with your '
              'class teacher or the school office.',
        ),
      ),
    );
  }
}

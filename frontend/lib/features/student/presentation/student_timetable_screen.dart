import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states/empty_state.dart';
import '../../../core/widgets/states/loading_skeleton.dart';
import '../../parent/data/parent_repository.dart';
import '../../parent/domain/parent_models.dart';
import '../../parent/presentation/class_timetable_screen.dart';
import 'student_timetable_unavailable.dart';

/// The student's own class timetable.
///
/// Depends on D-19 (PROPOSED `GET /api/students/me/enrollment`): the only safe
/// way for a student to learn their own section. Until that endpoint is
/// approved and deployed, any failure shows the existing honest "not
/// available yet" state. Nothing is guessed from section names and no
/// timetable data is invented. Once the enrollment is known, the week comes
/// from `GET /api/timetable/section/{id}`, which the backend already allows
/// for the enrolled student (assertCanReadSection).
class StudentTimetableScreen extends StatefulWidget {
  const StudentTimetableScreen({
    required this.repository,
    this.now,
    this.academyInstitution = false,
    super.key,
  });

  /// ACADEMY profile: a learner with no class placement studies in batches,
  /// shown under Courses.
  final bool academyInstitution;

  final ParentRepository repository;
  final DateTime Function()? now;

  @override
  State<StudentTimetableScreen> createState() => StudentTimetableScreenState();
}

enum _Phase { loading, unavailable, notEnrolled, ready }

class StudentTimetableScreenState extends State<StudentTimetableScreen> {
  _Phase _phase = _Phase.loading;
  OwnEnrollment? _enrollment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await widget.repository.loadOwnEnrollment();
      if (!mounted) return;
      setState(() {
        _enrollment = e;
        _phase = e == null ? _Phase.notEnrolled : _Phase.ready;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.unavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    switch (_phase) {
      case _Phase.loading:
        return Scaffold(
          backgroundColor: t.page,
          body: const SafeArea(child: LoadingSkeleton.listRows(count: 4)),
        );
      case _Phase.unavailable:
        return const StudentTimetableUnavailable(title: 'Timetable');
      case _Phase.notEnrolled:
        return Scaffold(
          backgroundColor: t.page,
          body: SafeArea(
            child: StateFrame(
              icon: Icons.schedule_outlined,
              iconColour: t.info,
              title: 'Not in a class this year',
              message: widget.academyInstitution
                  ? 'You are not placed in a school class. Your batch sessions '
                        'are listed under Courses.'
                  : 'You are not placed in a class for the current academic '
                        'year, so there is no timetable to show. Please check '
                        'with your institution office.',
            ),
          ),
        );
      case _Phase.ready:
        final e = _enrollment!;
        return ClassTimetableScreen(
          embedded: true,
          title: e.label.isEmpty ? 'Timetable' : 'Timetable · ${e.label}',
          now: widget.now,
          load: () => widget.repository.loadWeek(
            sectionId: e.sectionId,
            academicYearId: e.academicYearId,
          ),
        );
    }
  }
}

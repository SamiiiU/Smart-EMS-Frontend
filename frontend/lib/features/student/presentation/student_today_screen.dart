import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/error_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../academy/data/academy_repository.dart';
import '../../parent/data/parent_repository.dart';
import '../../parent/domain/parent_models.dart';
import '../../parent/presentation/child_attendance_screen.dart';
import '../../parent/presentation/parent_home_screen.dart'
    show ChildDay, ChildTodayCard, HistoryLink, ParentHomeScreenState;

/// The student's own Today.
///
/// Built only on approved, already-deployed reads: `GET /api/students/me` for
/// the student's id, then `GET /api/parent-progress/student/{ownId}`, which the
/// backend allows for the student themself (OwnershipService "own" rule; the
/// student role holds `diary.view`). It shows today's attendance, diary,
/// remarks, attendance summary, latest PUBLISHED result and pending work, the
/// same card a parent sees, so nothing new is exposed.
///
/// The class timetable is NOT shown: a student cannot read their own section
/// id from any endpoint they may call (D-19), and guessing it from a section
/// name is not safe.
class StudentTodayScreen extends StatefulWidget {
  const StudentTodayScreen({
    required this.repository,
    this.academy,
    this.now,
    super.key,
  });

  final ParentRepository repository;

  /// Set for an ACADEMY-profile institution, so an Academy learner's batches
  /// and sessions appear on the same card.
  final AcademyRepository? academy;
  final DateTime Function()? now;

  @override
  State<StudentTodayScreen> createState() => StudentTodayScreenState();
}

class StudentTodayScreenState extends State<StudentTodayScreen> {
  ScreenState<GuardianChild> _me = const ScreenState<GuardianChild>.loading();
  ScreenState<ChildDay> _today = const ScreenState<ChildDay>.loading();

  /// `/api/students/me` returned 404: a login with no student record (D-17).
  bool _notLinked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _me = ScreenState<GuardianChild>.loading(previous: _me.data);
      _notLinked = false;
    });
    try {
      final me = await widget.repository.loadOwnStudent();
      if (!mounted) return;
      setState(() => _me = ScreenState<GuardianChild>.data(me, isEmpty: false));
      await _loadToday(me);
    } on LoadFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _notLinked = failure.isNotLinked;
        _me = ScreenState<GuardianChild>.failed(failure, cached: _me.data);
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(
        () => _me = ScreenState<GuardianChild>.failed(
          const LoadFailure(),
          cached: _me.data,
        ),
      );
    }
  }

  Future<void> _loadToday(GuardianChild me) async {
    setState(() => _today = const ScreenState<ChildDay>.loading());
    try {
      final day = ChildDay(await widget.repository.loadToday(me.studentId));
      if (!mounted) return;
      setState(() => _today = ScreenState<ChildDay>.data(day, isEmpty: false));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _today = ScreenState<ChildDay>.failed(
          e is LoadFailure ? e : const LoadFailure(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (_notLinked) return const Scaffold(body: UnlinkedProfileState());

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ScreenStateBuilder<GuardianChild>(
          state: _me,
          onRetry: _load,
          emptyTitle: 'No student record',
          emptyMessage:
              'Ask your institution office to link your login to your student record.',
          data: (context, me) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ParentHomeScreenState.maxContentWidth,
              ),
              child: RefreshIndicator(
                onRefresh: () => _loadToday(me),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.space6),
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Today',
                        style: AppTypography.screenTitle.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space6),
                    ChildTodayCard(
                      child: me,
                      state: _today,
                      onRetry: () => _loadToday(me),
                      academy: widget.academy,
                      now: widget.now,
                    ),
                    if (_today.data?.school != null) ...[
                      const SizedBox(height: AppSpacing.space6),
                      HistoryLink(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChildAttendanceScreen(
                              repository: widget.repository,
                              child: me,
                              now: widget.now,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../domain/parent_models.dart';

/// A class's week, read-only: day chips, then that day's lessons in period
/// order with time, subject, teacher and room.
///
/// Fed by any loader of `GET /api/timetable/section/{id}`. Today a parent opens
/// it for a child (ids from guardians/me). A student will use the same view
/// once their own section id is available (D-19).
class ClassTimetableScreen extends StatefulWidget {
  const ClassTimetableScreen({
    required this.title,
    required this.load,
    this.now,
    this.embedded = false,
    super.key,
  });

  /// e.g. "Ali Khan · Grade 5-A".
  final String title;
  final Future<List<WeekLesson>> Function() load;
  final DateTime Function()? now;

  /// Inside a navigation tab: no app bar of its own.
  final bool embedded;

  static const List<(int, String)> days = [
    (1, 'Mon'),
    (2, 'Tue'),
    (3, 'Wed'),
    (4, 'Thu'),
    (5, 'Fri'),
    (6, 'Sat'),
  ];

  @override
  State<ClassTimetableScreen> createState() => ClassTimetableScreenState();
}

class ClassTimetableScreenState extends State<ClassTimetableScreen> {
  ScreenState<List<WeekLesson>> _state =
      const ScreenState<List<WeekLesson>>.loading();

  /// Opens on today (Sunday opens on Monday).
  late int _day = () {
    final wd = (widget.now?.call() ?? DateTime.now()).weekday;
    return wd >= 1 && wd <= 6 ? wd : 1;
  }();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
      () =>
          _state = ScreenState<List<WeekLesson>>.loading(previous: _state.data),
    );
    try {
      final week = await widget.load();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<WeekLesson>>.data(week));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ScreenState<List<WeekLesson>>.failed(
          e is LoadFailure ? e : const LoadFailure(),
          cached: _state.data,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      appBar: widget.embedded ? null : AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ScreenStateBuilder<List<WeekLesson>>(
          state: _state,
          onRetry: _load,
          emptyTitle: 'No timetable yet',
          emptyMessage:
              'The institution has not published lessons for this class yet.',
          emptyIcon: Icons.calendar_view_week_outlined,
          data: (context, week) => _week(context, week),
        ),
      ),
    );
  }

  Widget _week(BuildContext context, List<WeekLesson> week) {
    final t = context.tokens;
    final lessons = week.where((l) => l.dayOfWeek == _day).toList();
    final dayName = ClassTimetableScreen.days
        .firstWhere((d) => d.$1 == _day)
        .$2;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.space6),
            children: [
              if (widget.embedded) ...[
                Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    style: AppTypography.screenTitle.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space6),
              ],
              Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  for (final (day, label) in ClassTimetableScreen.days)
                    PickerChip(
                      label: label,
                      selected: day == _day,
                      onTap: () => setState(() => _day = day),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space6),
              if (lessons.isEmpty)
                Text(
                  'No lessons on $dayName.',
                  style: AppTypography.bodyParentStudent.copyWith(
                    color: t.textSecondary,
                  ),
                )
              else
                for (final l in lessons) _LessonRow(lesson: l),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final WeekLesson lesson;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final time = [
      lesson.startTime,
      lesson.endTime,
    ].whereType<String>().join('–');
    final who = [
      lesson.teacherName,
      lesson.roomName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Semantics(
      container: true,
      label:
          '${lesson.periodName}${time.isEmpty ? '' : ', $time'}: '
          '${lesson.subjectName}${who.isEmpty ? '' : ', $who'}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.space3),
          padding: const EdgeInsets.all(AppSpacing.space5),
          constraints: const BoxConstraints(
            minHeight: AppSizing.listRowMinHeight,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  lesson.periodName,
                  time,
                ].where((s) => s.isNotEmpty).join(' · '),
                style: AppTypography.overline.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                lesson.subjectName,
                style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
              ),
              if (who.isNotEmpty)
                Text(
                  who,
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

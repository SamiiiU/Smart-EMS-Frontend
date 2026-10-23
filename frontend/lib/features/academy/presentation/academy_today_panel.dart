import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'session_attendance_screen.dart';

/// Teacher Today, Academy part (report 11 A-2): the teacher's own DATED
/// course sessions for today, from `GET /api/academy/sessions/mine`.
///
/// - Only sessions the server returns (batches the teacher currently
///   instructs, current campus assignment); weekly templates are never shown
///   as confirmed sessions.
/// - The active campus narrows the list (CampusFilterInterceptor); a campus
///   switch reloads it, and a late answer for the old campus is rejected.
/// - "Take attendance" opens the existing online-only session sheet, and only
///   when the server says the teacher may mark (canMark). Academy attendance
///   never touches the School offline queue.
class AcademyTodayPanel extends StatefulWidget {
  const AcademyTodayPanel({
    required this.repository,
    this.campusChanges,
    this.now,
    super.key,
  });

  final AcademyRepository repository;
  final Listenable? campusChanges;
  final DateTime Function()? now;

  @override
  State<AcademyTodayPanel> createState() => _AcademyTodayPanelState();
}

class _AcademyTodayPanelState extends State<AcademyTodayPanel> {
  late Future<List<MySession>> _load = widget.repository.mySessions();

  void _reload() {
    if (!mounted) return;
    setState(() {
      _load = widget.repository.mySessions();
    });
  }

  @override
  void initState() {
    super.initState();
    widget.campusChanges?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.campusChanges?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _open(MySession s) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionAttendanceScreen(
          repository: widget.repository,
          session: s.session,
          title: '${s.courseName} · ${s.batchName}',
        ),
      ),
    );
    _reload(); // marked counts and status come from the server again
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final meta = AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space6,
        vertical: AppSpacing.space3,
      ),
      child: FutureBuilder<List<MySession>>(
        future: _load,
        builder: (context, snap) {
          final heading = Semantics(
            header: true,
            child: Text(
              'Course sessions today',
              style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
            ),
          );
          if (snap.connectionState != ConnectionState.done) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: AppSpacing.space3),
                const LinearProgressIndicator(),
              ],
            );
          }
          if (snap.hasError) {
            final f = snap.error;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: AppSpacing.space3),
                Text(
                  f is LoadFailure && f.unreachable
                      ? 'Could not reach the server for course sessions.'
                      : 'Could not load course sessions.',
                  style: meta,
                ),
                const SizedBox(height: AppSpacing.space3),
                AppButton(
                  label: 'Retry',
                  semanticsLabel: 'Retry course sessions',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  onPressed: _reload,
                ),
              ],
            );
          }
          final rows = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: AppSpacing.space3),
              if (rows.isEmpty)
                Text('No course sessions scheduled for you today.', style: meta)
              else
                for (final s in rows) ...[
                  _SessionCard(
                    item: s,
                    phase: _phase(s),
                    onOpen: s.canMark ? () => _open(s) : null,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                ],
            ],
          );
        },
      ),
    );
  }

  /// Upcoming / in progress / ended by the session's own times on today's
  /// date (the server already chose the day in the institution's timezone).
  String _phase(MySession s) {
    if (s.session.cancelled) return 'Cancelled';
    final now = (widget.now ?? DateTime.now)();
    final hhmm =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (hhmm.compareTo(s.session.start) < 0) return 'Upcoming';
    if (hhmm.compareTo(s.session.end) < 0) return 'In progress';
    return 'Ended';
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.item, required this.phase, this.onOpen});

  final MySession item;
  final String phase;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = item.session;
    final when = '${s.start}–${s.end}${s.room == null ? '' : ' · ${s.room}'}';
    final attendance = s.cancelled
        ? 'No attendance (cancelled)'
        : 'Marked ${item.marked} of ${item.activeLearners}';
    final title = '${item.courseName} · ${item.batchName}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One summary node for screen readers; the action stays separate.
          Semantics(
            container: true,
            label: '$title, $when, $phase, $attendance',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.personName.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    '$when · $phase',
                    style: AppTypography.bodyAdminMeta.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    attendance,
                    style: AppTypography.bodyAdminMeta.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onOpen != null) ...[
            const SizedBox(height: AppSpacing.space4),
            AppButton(
              key: Key('academy-today-open-${s.id}'),
              label: 'Take attendance',
              semanticsLabel: 'Take attendance, $title, ${s.start}',
              size: AppButtonSize.sm,
              onPressed: onOpen,
            ),
          ],
        ],
      ),
    );
  }
}

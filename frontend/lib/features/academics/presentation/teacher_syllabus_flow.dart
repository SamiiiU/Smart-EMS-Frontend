import 'package:flutter/material.dart';

import '../../../core/widgets/states/loading_skeleton.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/empty_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/academics_repository.dart';
import '../data/teacher_syllabus_context.dart';
import 'syllabus_screen.dart';

/// Teacher entry to Syllabus and coverage (owner decision, 18 Oct 2026).
///
/// Offers only the teacher's own assigned sections and subjects; publishing,
/// adopting and rejecting stay with Institution Admins (the review screen hides
/// them for a teacher and the server refuses them).
class TeacherSyllabusFlow extends StatefulWidget {
  const TeacherSyllabusFlow({
    required this.repository,
    required this.staffId,
    super.key,
  });

  final AcademicsRepository repository;
  final String? staffId;

  @override
  State<TeacherSyllabusFlow> createState() => _TeacherSyllabusFlowState();
}

class _TeacherSyllabusFlowState extends State<TeacherSyllabusFlow> {
  TeacherSyllabusContext? _context;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final staffId = widget.staffId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = staffId == null
          ? null
          : await widget.repository.teacherSyllabusContext(staffId);
      if (mounted) setState(() => _context = loaded);
    } on LoadFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message ?? 'Your subjects could not be loaded.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your subjects could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _context;
    if (_loading) {
      return Semantics(
        liveRegion: true,
        label: 'Loading your subjects',
        child: const LoadingSkeleton.listRows(count: 3),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            const SizedBox(height: AppSpacing.space4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: 'Try again',
                icon: Icons.refresh,
                variant: AppButtonVariant.secondary,
                onPressed: _load,
              ),
            ),
          ],
        ),
      );
    }
    if (loaded == null || loaded.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No subjects assigned to you',
        message:
            'Syllabus and coverage appear here for the sections and subjects you teach.',
      );
    }
    return SyllabusScreen(
      repository: widget.repository,
      year: loaded.year,
      classes: loaded.classes,
      sections: loaded.sections,
      subjects: loaded.subjects,
    );
  }
}

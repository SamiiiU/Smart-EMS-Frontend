import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../parent/data/parent_repository.dart';
import '../data/subject_resources_repository.dart';
import 'subject_resources_screen.dart' show ResourceRow, saveSubjectResource;

/// D-21, read-only: the subject resources of ONE learner's current class.
///
/// Used by the student (their own id) and by a guardian (the selected child).
/// The server derives the class and year from that learner's own current
/// enrollment and refuses anyone who is not the student or an approved
/// guardian, so nothing from another class or family can be shown. There are
/// no add or remove actions here, only Download and Copy link.
class LearnerResourcesScreen extends StatefulWidget {
  const LearnerResourcesScreen({
    required this.repository,
    required this.studentId,
    required this.title,
    this.embedded = false,
    super.key,
  });

  final SubjectResourcesRepository repository;
  final String studentId;

  /// e.g. "Resources" (student tab) or "Ali Khan · Resources" (guardian).
  final String title;

  /// Inside a navigation tab: no app bar of its own.
  final bool embedded;

  @override
  State<LearnerResourcesScreen> createState() => LearnerResourcesScreenState();
}

class LearnerResourcesScreenState extends State<LearnerResourcesScreen> {
  ScreenState<LearnerResources> _state =
      const ScreenState<LearnerResources>.loading();
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
      () =>
          _state = ScreenState<LearnerResources>.loading(previous: _state.data),
    );
    try {
      final r = await widget.repository.listForLearner(widget.studentId);
      if (!mounted) return;
      setState(
        () => _state = ScreenState<LearnerResources>.data(
          r,
          isEmpty: r.resources.isEmpty,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ScreenState<LearnerResources>.failed(
          e is LoadFailure ? e : const LoadFailure(),
          cached: _state.data,
        ),
      );
    }
  }

  Future<void> _save(SubjectResource r) async {
    final error = await saveSubjectResource(widget.repository, r);
    if (!mounted) return;
    setState(() {
      _error = error;
      _notice = null;
    });
  }

  Future<void> _copy(SubjectResource r) async {
    final url = r.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      setState(() {
        _notice = 'Link copied.';
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      appBar: widget.embedded ? null : AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ScreenStateBuilder<LearnerResources>(
          state: _state,
          onRetry: _load,
          emptyTitle: 'No resources yet',
          emptyMessage: _state.data?.notPlaced == true
              ? 'Not placed in a class this year, so there are no class '
                    'resources to show.'
              : 'Books, notes and links added by teachers for this class '
                    'appear here.',
          emptyIcon: Icons.folder_outlined,
          data: (context, data) => _list(context, data),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, LearnerResources data) {
    final t = context.tokens;
    // Group by subject, keeping the server's order (subject, newest first).
    final groups = <String, List<SubjectResource>>{};
    for (final r in data.resources) {
      groups.putIfAbsent(r.subjectName ?? 'Other', () => []).add(r);
    }
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
                const SizedBox(height: AppSpacing.space2),
              ],
              if (data.className != null)
                Text(
                  [
                    data.className,
                    data.academicYearName,
                  ].whereType<String>().join(' · '),
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
              const SizedBox(height: AppSpacing.space4),
              if (_notice != null) ...[
                InlineAlert(tone: InlineAlertTone.success, message: _notice!),
                const SizedBox(height: AppSpacing.space3),
              ],
              if (_error != null) ...[
                InlineAlert(tone: InlineAlertTone.danger, message: _error!),
                const SizedBox(height: AppSpacing.space3),
              ],
              for (final entry in groups.entries) ...[
                Semantics(
                  header: true,
                  child: Text(
                    entry.key,
                    style: AppTypography.sectionHeading.copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space3),
                for (final r in entry.value)
                  ResourceRow(
                    resource: r,
                    onSave: r.isLink ? null : () => _save(r),
                    onCopy: r.isLink ? () => _copy(r) : null,
                  ),
                const SizedBox(height: AppSpacing.space4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Student "Resources" tab: resolves the student's own id
/// (GET /api/students/me), then shows their class's resources.
class StudentResourcesFlow extends StatefulWidget {
  const StudentResourcesFlow({
    required this.parent,
    required this.repository,
    super.key,
  });

  final ParentRepository parent;
  final SubjectResourcesRepository repository;

  @override
  State<StudentResourcesFlow> createState() => _StudentResourcesFlowState();
}

class _StudentResourcesFlowState extends State<StudentResourcesFlow> {
  ScreenState<String> _me = const ScreenState<String>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _me = const ScreenState<String>.loading());
    try {
      final me = await widget.parent.loadOwnStudent();
      if (mounted) {
        setState(
          () => _me = ScreenState<String>.data(me.studentId, isEmpty: false),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _me = ScreenState<String>.failed(
            e is LoadFailure ? e : const LoadFailure(),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _me.data;
    if (id != null) {
      return LearnerResourcesScreen(
        repository: widget.repository,
        studentId: id,
        title: 'Resources',
        embedded: true,
      );
    }
    return Scaffold(
      backgroundColor: context.tokens.page,
      body: SafeArea(
        child: ScreenStateBuilder<String>(
          state: _me,
          onRetry: _load,
          emptyTitle: 'No student record',
          emptyMessage:
              'Ask your institution office to link your login to your '
              'student record.',
          data: (context, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

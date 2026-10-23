import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/states/empty_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

/// V62: a published curriculum version is immutable. This screen never edits a
/// publication; it only drafts, publishes, rejects or adopts through the server.
class CurriculumReviewScreen extends StatefulWidget {
  const CurriculumReviewScreen({
    required this.repository,
    required this.chapter,
    super.key,
  });
  final AcademicsRepository repository;
  final Chapter chapter;
  @override
  State<CurriculumReviewScreen> createState() => _CurriculumReviewScreenState();
}

String _failure(Object e, String fallback) =>
    e is LoadFailure ? (e.message ?? fallback) : fallback;

String _when(Object? iso) {
  final at = iso == null ? null : DateTime.tryParse('$iso');
  return at == null
      ? '${iso ?? 'Unknown'}'
      : DateFormat.yMMMd().format(at.toLocal());
}

/// Publication content is `{chapter: {...}, topics: [{...}]}`.
String? _chapterName(Object? content) {
  final chapter = content is Map ? content['chapter'] : null;
  return chapter is Map && chapter['name'] is String
      ? chapter['name'] as String
      : null;
}

List<String> _topicNames(Object? content) {
  final topics = content is Map ? content['topics'] : null;
  return topics is List
      ? [
          for (final topic in topics)
            if (topic is Map && topic['name'] is String)
              topic['name'] as String,
        ]
      : const [];
}

class _CurriculumReviewScreenState extends State<CurriculumReviewScreen> {
  List<Map<String, dynamic>>? versions;
  final selected = <String>{};
  String reason = '', name = '';
  String? error;
  bool busy = false, loading = true, adopt = false, finished = false;
  @override
  void initState() {
    super.initState();
    name = widget.chapter.name;
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final rows = await widget.repository.curriculumVersions(
        widget.chapter.id,
      );
      if (mounted) {
        setState(() {
          versions = rows;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = _failure(e, 'Curriculum versions could not be loaded.'),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) setState(() => finished = true);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = _failure(e, 'Not saved. Refresh before retrying.'),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Irreversible steps (publish, adopt, reject) need an explicit confirmation.
  Future<void> _confirmThen(
    String title,
    String message,
    String label,
    Future<void> Function() action,
  ) async {
    final ok = await confirmAction(
      context,
      title: title,
      message: message,
      confirmLabel: label,
      irreversible: true,
    );
    if (ok && mounted) await _run(action);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = widget.chapter;
    final enabled = !busy && !finished && versions != null;
    const gap = SizedBox(height: AppSpacing.space5);
    final reasonOk = reason.trim().isNotEmpty;
    // DEF-14: only a proposed draft can be reviewed; published content is immutable.
    final reviewable = c.canPublish && c.status == 'proposed';
    // Result feedback sits next to the actions that produce it (publishers scroll down to act),
    // otherwise at the top, so the outcome is always visible where the user is.
    final feedback = <Widget>[
      if (error != null) ...[
        InlineAlert(
          key: const Key('curriculum-error'),
          tone: InlineAlertTone.danger,
          message: error!,
        ),
        gap,
      ],
      if (finished) ...[
        const InlineAlert(
          tone: InlineAlertTone.success,
          message:
              'Saved. Return to the syllabus to refresh available actions.',
        ),
        gap,
      ],
    ];
    return SetupScaffold(
      title: 'Curriculum review',
      note: Text(
        c.adopted
            ? 'Adopted official curriculum'
            : 'Draft or legacy content; explicit review is required for official use.',
      ),
      children: [
        Semantics(
          header: true,
          child: Text(c.name, style: AppTypography.sectionHeading),
        ),
        gap,
        if (loading || busy) ...[
          Semantics(
            liveRegion: true,
            label: 'Loading',
            child: const LinearProgressIndicator(),
          ),
          gap,
        ],
        if (!reviewable) ...feedback,
        if (versions == null && !loading) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: 'Load versions',
              icon: Icons.refresh,
              variant: AppButtonVariant.secondary,
              onPressed: busy ? null : _load,
            ),
          ),
          gap,
        ],
        if (c.canEdit) ...[
          SectionCard(
            title: 'Draft',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  key: const Key('curriculum-draft-name'),
                  label: 'Draft chapter name',
                  value: name,
                  onChanged: (v) => setState(() => name = v),
                ),
                gap,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton(
                    label: 'Save draft name',
                    variant: AppButtonVariant.secondary,
                    onPressed: enabled && name.trim().isNotEmpty
                        ? () => _run(
                            () => widget.repository.renameCurriculumDraft(
                              c.id,
                              name.trim(),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          gap,
        ],
        if (c.status == 'active') ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: 'Create draft revision',
              variant: AppButtonVariant.secondary,
              onPressed: enabled
                  ? () => _run(
                      () => widget.repository.curriculumAction(
                        'chapters/${c.id}/draft-revision',
                      ),
                    )
                  : null,
            ),
          ),
          gap,
        ],
        if (reviewable) ...[
          SectionCard(
            title: 'Review and publish',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select exactly the reviewed topics; no topics are selected automatically.',
                  style: AppTypography.bodyTeacher,
                ),
                Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final topic in c.topics)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            topic.name,
                            style: AppTypography.bodyTeacher,
                          ),
                          value: selected.contains(topic.id),
                          onChanged: enabled
                              ? (v) => setState(() {
                                  if (v == true) {
                                    selected.add(topic.id);
                                  } else {
                                    selected.remove(topic.id);
                                  }
                                })
                              : null,
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Adopt this version for official reports',
                          style: AppTypography.bodyTeacher,
                        ),
                        value: adopt,
                        onChanged: enabled
                            ? (v) => setState(() => adopt = v)
                            : null,
                      ),
                    ],
                  ),
                ),
                gap,
                AppTextField(
                  key: const Key('curriculum-reason'),
                  label: 'Review reason',
                  required: true,
                  value: reason,
                  onChanged: (v) => setState(() => reason = v),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  reasonOk
                      ? 'Saved with the decision.'
                      : 'Required before publishing or rejecting.',
                  style: AppTypography.caption.copyWith(color: t.textSecondary),
                ),
                gap,
                ...feedback,
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.space4,
                  runSpacing: AppSpacing.space4,
                  children: [
                    if (c.status == 'proposed')
                      AppButton(
                        label: 'Reject draft',
                        variant: AppButtonVariant.secondary,
                        onPressed: enabled && reasonOk
                            ? () => _confirmThen(
                                'Reject this draft?',
                                'The proposed draft will be closed with your reason.',
                                'Reject draft',
                                () => widget.repository.curriculumAction(
                                  'chapters/${c.id}/reject',
                                  {'reason': reason.trim()},
                                ),
                              )
                            : null,
                      ),
                    AppButton(
                      label: 'Publish reviewed version',
                      onPressed: enabled && reasonOk
                          ? () => _confirmThen(
                              'Publish this version?',
                              'A published version is permanent and cannot be edited. '
                                  '${selected.length} reviewed topic(s) will be included'
                                  '${adopt ? ', and it will become the official version for reports' : ''}.',
                              'Publish',
                              () => widget.repository.curriculumAction(
                                'chapters/${c.id}/publish',
                                {
                                  'expectedPreviousVersion': versions!.isEmpty
                                      ? null
                                      : versions!.first['id'],
                                  'topicIds': selected.toList(),
                                  'adopt': adopt,
                                  'reason': reason.trim(),
                                },
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          gap,
        ],
        Semantics(
          header: true,
          child: Text('Published versions', style: AppTypography.cardHeading),
        ),
        const SizedBox(height: AppSpacing.space4),
        if (versions != null && versions!.isEmpty)
          const EmptyState(
            icon: Icons.history_edu_outlined,
            title: 'No published versions yet',
            message:
                'Reviewed versions appear here once published. They cannot be edited afterwards.',
          ),
        for (final v in versions ?? <Map<String, dynamic>>[]) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${v['version']} - ${v['adopted'] == true ? 'Adopted' : 'Published'}',
                  style: AppTypography.cardHeading,
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'Published: ${_when(v['published_at'])}',
                  style: AppTypography.bodyTeacher,
                ),
                Text(
                  'Reason: ${v['reason']}',
                  style: AppTypography.bodyTeacher,
                ),
                // DEF-15: show the reviewed names only, never the raw stored record.
                Text(
                  'Chapter: ${_chapterName(v['content']) ?? c.name}',
                  style: AppTypography.bodyTeacher,
                ),
                Text(
                  _topicNames(v['content']).isEmpty
                      ? 'Topics: none'
                      : 'Topics: ${_topicNames(v['content']).join(', ')}',
                  style: AppTypography.bodyTeacher,
                ),
                const SizedBox(height: AppSpacing.space2),
                if (v['content_hash'] is String &&
                    (v['content_hash'] as String).length >= 12)
                  Text(
                    'Fingerprint: ${(v['content_hash'] as String).substring(0, 12)}',
                    style: AppTypography.caption.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                if (c.canPublish && v['adopted'] != true) ...[
                  const SizedBox(height: AppSpacing.space4),
                  AppButton(
                    label: 'Adopt version',
                    semanticsLabel:
                        'Adopt version ${v['version']} for official reports',
                    variant: AppButtonVariant.secondary,
                    onPressed: enabled
                        ? () => _confirmThen(
                            'Adopt version ${v['version']}?',
                            'This version becomes the official curriculum used in reports.',
                            'Adopt version',
                            () => widget.repository.curriculumAction(
                              'publications/${v['id']}/adopt',
                            ),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
        ],
      ],
    );
  }
}

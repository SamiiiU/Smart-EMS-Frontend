import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/diary_repository.dart';
import '../domain/diary_models.dart';

/// What the editor loaded: the existing entry, or none yet.
///
/// A wrapper rather than `DiaryEntry?` so that "no entry yet" is a LOADED
/// value, never confused with "not loaded" — the distinction this screen is
/// built around.
class DiaryLoad {
  const DiaryLoad(this.existing);

  final DiaryEntry? existing;
}

/// Today's diary for one period — edit-first.
///
/// Opened from a period, because the period is the one place that already
/// knows both halves of the backend's key (section + subject). The existing
/// entry is looked up silently before the teacher types:
///
/// - **exists** → the form opens pre-filled and saving is an UPDATE;
/// - **none yet** → the form opens blank and saving is a CREATE. That is a
///   normal state, said plainly, never rendered as an error.
///
/// A 409 can then only come from a genuine race (another tab or device saved
/// first). It surfaces as a real error with a reload — never swallowed,
/// because a swallowed 409 tells the teacher their words were saved when
/// they were discarded.
class DiaryEditorScreen extends StatefulWidget {
  const DiaryEditorScreen({
    required this.repository,
    required this.diaryKey,
    required this.heading,
    this.subjectLabel,
    this.currentTeacherName,
    super.key,
  });

  final DiaryRepository repository;
  final DiaryKey diaryKey;

  /// e.g. the section label, shown as the screen title.
  final String heading;
  final String? subjectLabel;

  /// The signed-in teacher's "First Last". Diary entries carry only an author
  /// NAME, and are shared per subject, so this is how an entry someone else
  /// wrote is recognised. Null when unknown — the author is then always shown.
  final String? currentTeacherName;

  @override
  State<DiaryEditorScreen> createState() => DiaryEditorScreenState();
}

class DiaryEditorScreenState extends State<DiaryEditorScreen> {
  ScreenState<DiaryLoad> _state = const ScreenState<DiaryLoad>.loading();

  DiaryDraft _draft = const DiaryDraft();

  /// Bumped whenever the draft is replaced from the server, so the text
  /// fields — which own their controllers — rebuild with the new content.
  int _formGeneration = 0;

  bool _saving = false;
  String? _saveError;
  bool _conflict = false;
  bool _saved = false;

  DiaryEntry? get _existing => _state.data?.existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = ScreenState<DiaryLoad>.loading(previous: _state.data);
      _saveError = null;
      _conflict = false;
    });
    try {
      final existing = await widget.repository.findExisting(widget.diaryKey);
      if (!mounted) return;
      setState(() {
        _state = ScreenState<DiaryLoad>.data(
          DiaryLoad(existing),
          // Loaded is loaded: "no entry yet" is rendered as a blank form,
          // not as the generic empty state.
          isEmpty: false,
        );
        _draft = existing == null
            ? const DiaryDraft()
            : DiaryDraft.fromEntry(existing);
        _formGeneration++;
      });
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<DiaryLoad>.failed(
            failure,
            cached: _state.data,
            connection: failure.unreachable
                ? NetworkStatus.offline
                : NetworkStatus.online,
          ));
    }
  }

  Future<void> save() async {
    if (_saving || _state.status != ScreenStatus.loaded) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _conflict = false;
      _saved = false;
    });

    final existing = _existing;
    try {
      final entry = existing == null
          ? await widget.repository.create(widget.diaryKey, _draft)
          : await widget.repository.update(
              existing.id,
              widget.diaryKey,
              _draft,
            );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
        // From here on this is an edit: the next save must be a PUT.
        _state = ScreenState<DiaryLoad>.data(DiaryLoad(entry), isEmpty: false);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(() {
        _saving = false;
        _conflict = failure.message == _conflictMessage;
        _saveError = failure.unreachable
            ? 'You are offline, so this was not saved. Your text is still '
                'here — save again when you are back online.'
            : _conflict
                ? 'Someone else saved this diary at the same time, so your '
                    'version was NOT saved. Reload to see theirs, then add '
                    'your changes.'
                : (failure.message ?? 'The diary could not be saved.');
      });
    }
  }

  /// The backend's verbatim 409 body message (verified live 2026-09-18).
  static const String _conflictMessage = 'Conflicts with existing data';

  bool get _writtenBySomeoneElse {
    final author = _existing?.authorName;
    if (author == null || author.isEmpty) return false;
    final me = widget.currentTeacherName;
    return me == null || me.trim().toLowerCase() != author.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(
        backgroundColor: t.surface,
        surfaceTintColor: t.surface,
        iconTheme: IconThemeData(color: t.textPrimary),
        title: Text(
          widget.heading,
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ScreenStateBuilder<DiaryLoad>(
          state: _state,
          onRetry: _load,
          emptyTitle: 'No diary entry yet',
          emptyMessage: 'Nothing has been written for this period. Add '
              'homework, a note or a reminder for the class.',
          data: (context, load) => _form(context, load),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, DiaryLoad load) {
    final t = context.tokens;
    final existing = load.existing;
    final fieldState =
        _saving ? AppTextFieldState.disabled : AppTextFieldState.normal;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space6),
      children: [
        Text(
          [
            if (widget.subjectLabel != null) widget.subjectLabel!,
            widget.diaryKey.dateParam,
          ].join(' · '),
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),

        // "No entry yet" is the normal start of a day — said as a fact, in a
        // neutral tone, never as an error.
        if (existing == null)
          const InlineAlert(
            tone: InlineAlertTone.info,
            message: 'No diary written for this period yet. Saving will '
                'create it.',
          )
        // Shared entry: the backend keys the diary per SUBJECT, so a
        // colleague who teaches the same subject to this section writes
        // into the same entry. Without this the teacher opens "their" diary
        // to find text they did not write.
        else if (_writtenBySomeoneElse)
          InlineAlert(
            tone: InlineAlertTone.info,
            message: 'Last saved by ${existing.authorName}. Everyone who '
                'teaches this subject to this section shares one diary '
                'entry per day.',
          ),
        const SizedBox(height: AppSpacing.space6),

        KeyedSubtree(
          key: ValueKey(_formGeneration),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Title (optional)',
                value: _draft.title,
                state: fieldState,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(title: v);
                  _saved = false;
                }),
              ),
              const SizedBox(height: AppSpacing.space5),
              _MultilineField(
                label: 'Classwork',
                value: _draft.classwork,
                enabled: !_saving,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(classwork: v);
                  _saved = false;
                }),
              ),
              const SizedBox(height: AppSpacing.space5),
              _MultilineField(
                label: 'Homework',
                value: _draft.homework,
                enabled: !_saving,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(homework: v);
                  _saved = false;
                }),
              ),
              const SizedBox(height: AppSpacing.space5),
              _MultilineField(
                label: 'Note to parents (optional)',
                value: _draft.note,
                enabled: !_saving,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(note: v);
                  _saved = false;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        if (_saveError != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _saveError!),
          const SizedBox(height: AppSpacing.space4),
          if (_conflict) ...[
            AppButton(
              label: 'Reload',
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              onPressed: _load,
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
        ],
        if (_saved) ...[
          const InlineAlert(tone: InlineAlertTone.success, message: 'Saved.'),
          const SizedBox(height: AppSpacing.space4),
        ],
        AppButton(
          label: _saving ? 'Saving…' : 'Save',
          fullWidth: true,
          // A blank NEW entry is not worth creating; a blank EXISTING entry
          // is a deliberate clear and may be saved.
          onPressed:
              _saving || (existing == null && _draft.isBlank) ? null : save,
        ),
      ],
    );
  }
}

/// A labelled multi-line field in the design system's tokens.
///
/// `AppTextField` is single-line and fixed-height by design (see
/// `csv_import_screen.dart` for the same reasoning); diary text is
/// paragraphs.
class _MultilineField extends StatefulWidget {
  const _MultilineField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_MultilineField> createState() => _MultilineFieldState();
}

class _MultilineFieldState extends State<_MultilineField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Container(
          constraints:
              const BoxConstraints(minHeight: AppSizing.diaryFieldMinHeight),
          padding: const EdgeInsets.all(AppSpacing.space4),
          decoration: BoxDecoration(
            color: widget.enabled ? t.surface : t.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Semantics(
            label: widget.label,
            textField: true,
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              onChanged: widget.onChanged,
              style: AppTypography.bodyAdminMeta
                  .copyWith(color: t.textPrimary),
              decoration: const InputDecoration.collapsed(hintText: null),
            ),
          ),
        ),
      ],
    );
  }
}

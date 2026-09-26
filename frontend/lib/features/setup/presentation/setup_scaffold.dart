import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/motion_reveal.dart';

/// Shared chrome for the setup screens: a titled page with an optional
/// note and a create panel.
///
/// Exists so the six screens of Batch A look and behave as one thing — no
/// new visual decisions, just the existing primitives arranged the same way
/// each time.
class SetupScaffold extends StatelessWidget {
  const SetupScaffold({
    required this.title,
    required this.children,
    this.note,
    super.key,
  });

  final String title;

  /// One line stating the rule that governs this screen — which year is in
  /// use, or what cannot be changed here. Always an explanation, never a
  /// disabled control.
  final Widget? note;
  final List<Widget> children;

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
          title,
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          children: [
            if (note != null) ...[
              note!,
              const SizedBox(height: AppSpacing.space5),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A card holding a create form. Collapsed to a single button until the
/// admin asks for it, so a long list is not pushed down by a form nobody is
/// using.
class CreatePanel extends StatefulWidget {
  const CreatePanel({
    required this.addLabel,
    required this.fields,
    required this.onSubmit,
    this.canSubmit = true,
    this.confirmNote,
    super.key,
  });

  final String addLabel;
  final List<Widget> fields;

  /// Runs the write. Returns an error message to show, or null on success.
  final Future<String?> Function() onSubmit;
  final bool canSubmit;

  /// Shown above the submit button when the action cannot be undone —
  /// stated BEFORE the action, not after it.
  final String? confirmNote;

  @override
  State<CreatePanel> createState() => CreatePanelState();
}

class CreatePanelState extends State<CreatePanel> {
  bool _open = false;
  bool _busy = false;
  String? _error;

  Future<void> submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _open = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (!_open) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space5),
        child: AppButton(
          label: widget.addLabel,
          icon: Icons.add,
          fullWidth: true,
          onPressed: () => setState(() => _open = true),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space5),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.addLabel,
            style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space5),
          ...widget.fields,
          if (widget.confirmNote != null) ...[
            const SizedBox(height: AppSpacing.space5),
            Text(
              widget.confirmNote!,
              style: AppTypography.bodyAdminMeta
                  .copyWith(color: t.warningTextOnBg),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.space4),
            Text(
              _error!,
              style: AppTypography.bodyAdminMeta.copyWith(color: t.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.space6),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: _busy ? null : () => setState(() => _open = false),
                ),
              ),
              const SizedBox(width: AppSpacing.space4),
              Expanded(
                child: AppButton(
                  label: _busy ? 'Saving…' : 'Save',
                  fullWidth: true,
                  onPressed: _busy || !widget.canSubmit ? null : submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A plain row for a created thing. Read-only by design in Batch A: this
/// backend's deletes orphan data and its edits do not exist, so no row
/// offers an action it cannot honour (D-19).
class SetupRow extends StatelessWidget {
  const SetupRow({
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? detail;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final row = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints:
          const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: AppTypography.bodyAdminMeta
                        .copyWith(color: t.textSecondary),
                  ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: AppTypography.overline
                        .copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: t.textSecondary),
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}

/// One numbered step on a hub screen.
///
/// A blocked step is INERT and says what is missing — never a disabled
/// control with no explanation (D-19). Lives here rather than in either hub
/// because both the Setup hub (T13) and the Finance hub (T14) are the same
/// idea: an ordered list of steps where each needs the one above it.
class StepRow extends StatelessWidget {
  const StepRow({
    required this.number,
    required this.title,
    required this.detail,
    this.count,
    this.onTap,
    this.blockedReason,
    super.key,
  });

  final int number;
  final String title;
  final String detail;
  final int? count;
  final VoidCallback? onTap;
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final blocked = blockedReason != null;

    final row = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints:
          const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.space8,
            height: AppSpacing.space8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: blocked ? t.surfaceSunken : t.primarySubtle,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              '$number',
              style: AppTypography.overline.copyWith(
                color: blocked ? t.textSecondary : t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: AppTypography.personName
                          .copyWith(color: t.textPrimary),
                    ),
                    if (count != null)
                      Text(
                        '$count',
                        style: AppTypography.overline
                            .copyWith(color: t.textSecondary),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  blockedReason ?? detail,
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: blocked ? t.warningTextOnBg : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: t.textSecondary),
        ],
      ),
    );

    // D-29 section reveal, staggered. The step's own [number] IS the stagger
    // index — these hubs are ordered lists where step 1 must read as coming
    // before step 2, so the motion carries the same meaning the numbers do.
    // Doing it here rather than at all nineteen call sites means a new step
    // cannot forget to join the sequence.
    return MotionReveal.staggered(
      index: number - 1,
      child: onTap == null
          ? row
          : Semantics(
              button: true,
              label: title,
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: ExcludeSemantics(child: row),
              ),
            ),
    );
  }
}

/// A labelled field, so the six screens build forms the same way.
class SetupField extends StatelessWidget {
  const SetupField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    super.key,
  });

  final String label;
  final String value;
  final String? placeholder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.space4),
        child: AppTextField(
          label: label,
          value: value,
          placeholder: placeholder,
          onChanged: onChanged,
        ),
      );
}

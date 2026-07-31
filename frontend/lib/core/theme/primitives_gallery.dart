import 'package:flutter/material.dart';

import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/avatar.dart';
import '../widgets/overline.dart';
import '../widgets/progress_bar.dart';
import '../widgets/status_pill.dart';
import 'app_theme.dart';
import 'scales.dart';
import 'sizing.dart';
import 'typography.dart';

/// The primitives half of the living gallery (T2).
///
/// Shows every variant of every primitive so T2 can be reviewed by looking at
/// it. Lives in `lib/core/theme/` alongside the token gallery because it is a
/// reference surface, not a product screen.
class PrimitivesGallerySection extends StatelessWidget {
  const PrimitivesGallerySection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Primitives'),
        const SizedBox(height: AppSpacing.space2),
        const _Note(
          'Six primitives. Every variant below is rendered from the same token '
          'set as the section above — none of them contains a literal colour, '
          'spacing, radius, or size.',
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- StatusPill ------------------------------------------------
        const _Heading('StatusPill — attendance (colour + letter + shape, D-21)'),
        const SizedBox(height: AppSpacing.space2),
        const _Note(
          'Each attendance status carries all three signals together. A '
          'colour-only variant is not expressible through this API.',
        ),
        const SizedBox(height: AppSpacing.space5),
        for (final size in StatusPillSize.values) ...[
          Text(
            'size: ${size.name}',
            style: AppTypography.overline.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space4,
            children: [
              for (final s in AppStatus.values.where((s) => s.isAttendance))
                StatusPill(status: s, size: size),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          // showLabel: false is only representable at md, because only the
          // 22px glyph carries a 13px letter (D-37). At sm the pill has no
          // letter, so hiding the word would leave colour alone.
          if (StatusPill.letterFitsAt(size)) ...[
            Text(
              'size: ${size.name}, showLabel: false — glyph + 13px letter',
              style: AppTypography.overline.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: AppSpacing.space3),
            Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space4,
              children: [
                for (final s in AppStatus.values.where((s) => s.isAttendance))
                  StatusPill(status: s, size: size, showLabel: false),
              ],
            ),
          ] else
            Text(
              'size: ${size.name} — shape only, no letter at 12px, so '
              'showLabel: false is unrepresentable (D-37)',
              style: AppTypography.overline.copyWith(color: t.textMuted),
            ),
          const SizedBox(height: AppSpacing.space6),
        ],

        const _Heading('StatusPill — entity (label only)'),
        const SizedBox(height: AppSpacing.space4),
        for (final size in StatusPillSize.values) ...[
          Text(
            'size: ${size.name}',
            style: AppTypography.overline.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space4,
            children: [
              for (final s in AppStatus.values.where((s) => !s.isAttendance))
                StatusPill(status: s, size: size),
            ],
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
        const SizedBox(height: AppSpacing.space6),

        // --- Avatar ----------------------------------------------------
        const _Heading('Avatar'),
        const SizedBox(height: AppSpacing.space4),
        for (final tone in AvatarTone.values) ...[
          Text(
            'tone: ${tone.name}',
            style: AppTypography.overline.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final size in AvatarSize.values) ...[
                Avatar(
                  initials: 'AK',
                  size: size,
                  tone: tone,
                  status: tone == AvatarTone.semantic ? AppStatus.absent : null,
                ),
                const SizedBox(width: AppSpacing.space5),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
        const SizedBox(height: AppSpacing.space6),

        // --- AppButton -------------------------------------------------
        const _Heading('AppButton'),
        const SizedBox(height: AppSpacing.space2),
        const _Note(
          'Heights come from AppSizing. On touch platforms every size is '
          'raised to the 44px touch-target minimum, so sm and md render at the '
          'same height on mobile — deliberate, not a bug.',
        ),
        const SizedBox(height: AppSpacing.space5),
        for (final variant in AppButtonVariant.values) ...[
          Text(
            'variant: ${variant.name}',
            style: AppTypography.overline.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space4,
            runSpacing: AppSpacing.space4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final size in AppButtonSize.values)
                AppButton(
                  label: size.name,
                  variant: variant,
                  size: size,
                  onPressed: () {},
                ),
              AppButton(
                label: 'with icon',
                variant: variant,
                icon: Icons.check,
                onPressed: () {},
              ),
              AppButton(label: 'disabled', variant: variant),
            ],
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
        Text(
          'fullWidth: true',
          style: AppTypography.overline.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: AppSpacing.space3),
        AppButton(label: 'Mark attendance', fullWidth: true, onPressed: () {}),
        const SizedBox(height: AppSpacing.space8),

        // --- AppTextField ----------------------------------------------
        const _Heading('AppTextField'),
        const SizedBox(height: AppSpacing.space4),
        const AppTextField(
          label: 'Default (empty, placeholder)',
          placeholder: 'e.g. Ayesha Khan',
        ),
        const SizedBox(height: AppSpacing.space6),
        const AppTextField(
          label: 'Default (with value)',
          value: 'Ayesha Khan',
        ),
        const SizedBox(height: AppSpacing.space6),
        const AppTextField(
          label: 'Focused',
          value: 'Ayesha Khan',
          state: AppTextFieldState.focused,
        ),
        const SizedBox(height: AppSpacing.space6),
        const AppTextField(
          label: 'Error',
          value: '03001234',
          state: AppTextFieldState.error,
          errorText: 'Enter a valid 11-digit mobile number',
        ),
        const SizedBox(height: AppSpacing.space6),
        const AppTextField(
          label: 'Disabled',
          value: 'Cannot edit',
          state: AppTextFieldState.disabled,
        ),
        const SizedBox(height: AppSpacing.space6),
        const AppTextField(
          label: 'Obscured, with trailing',
          value: 'secret123',
          obscure: true,
          trailing: Icon(Icons.visibility_off, size: AppSpacing.space6),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- Overline --------------------------------------------------
        const _Heading('Overline'),
        const SizedBox(height: AppSpacing.space4),
        const Overline('Today at a glance'),
        const SizedBox(height: AppSpacing.space3),
        const Overline('Class 9-C · section b'),
        const SizedBox(height: AppSpacing.space8),

        // --- ProgressBar -----------------------------------------------
        const _Heading('ProgressBar'),
        const SizedBox(height: AppSpacing.space2),
        const _Note(
          'Threshold: >= 75% success, < 75% warning. Two tiers only — there is '
          'deliberately no third danger tier.',
        ),
        const SizedBox(height: AppSpacing.space5),
        for (final pct in <double>[0, 42, 74, 75, 88, 100]) ...[
          Row(
            children: [
              SizedBox(
                width: AppSizing.avatar56,
                child: Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: AppTypography.fieldLabel.copyWith(
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space5),
              Expanded(child: ProgressBar(percent: pct)),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
    );
  }
}

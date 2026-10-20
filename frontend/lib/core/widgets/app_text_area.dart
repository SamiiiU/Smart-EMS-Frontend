import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';

/// The design system's multi-line text area.
///
/// `AppTextField` is deliberately single-line and fixed-height (form fields);
/// paragraphs and pasted rows need a growing field. This is that field, in the
/// same tokens, so screens do not each hand-build one.
///
/// The caller owns [controller] (and therefore the text): the field never
/// resyncs from a `value` on rebuild, so typed text is never lost (DEF-12).
class AppTextArea extends StatelessWidget {
  const AppTextArea({
    required this.controller,
    required this.semanticsLabel,
    required this.minHeight,
    this.semanticsHint,
    this.placeholder,
    this.enabled = true,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;

  /// What a screen reader announces for the field.
  final String semanticsLabel;
  final String? semanticsHint;

  /// Greyed example text shown while empty.
  final String? placeholder;
  final double minHeight;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: enabled ? t.surface : t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Semantics(
        label: semanticsLabel,
        hint: semanticsHint,
        child: TextField(
          controller: controller,
          enabled: enabled,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          onChanged: onChanged,
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
          decoration: InputDecoration.collapsed(
            hintText: placeholder,
            hintStyle: AppTypography.bodyAdminMeta.copyWith(
              color: t.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}

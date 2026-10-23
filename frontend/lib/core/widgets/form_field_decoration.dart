import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';

/// Design-system look for a Material `TextFormField`, for screens that must keep
/// `Form` validation (OBS-02) and so cannot use [AppTextField]. Same tokens as
/// [AppTextField]: thin border at rest, thick primaryAccent when focused, thick
/// danger on error, surface fill.
InputDecoration appFormDecoration(
  BuildContext context, {
  required String label,
  String? helper,
}) {
  final t = context.tokens;
  OutlineInputBorder edge(Color colour, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: colour, width: width),
  );
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 3,
    errorMaxLines: 3,
    filled: true,
    fillColor: t.surface,
    labelStyle: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
    helperStyle: AppTypography.caption.copyWith(color: t.textSecondary),
    errorStyle: AppTypography.fieldLabel.copyWith(color: t.danger),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.space5,
      vertical: AppSpacing.space4,
    ),
    border: edge(t.border, AppSizing.borderThin),
    enabledBorder: edge(t.border, AppSizing.borderThin),
    disabledBorder: edge(t.border, AppSizing.borderThin),
    focusedBorder: edge(t.primaryAccent, AppSizing.borderThick),
    errorBorder: edge(t.danger, AppSizing.borderThick),
    focusedErrorBorder: edge(t.danger, AppSizing.borderThick),
  );
}

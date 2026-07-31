import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import 'app_button.dart' show isTouchPlatform;

enum AppTextFieldState { normal, focused, error, disabled }

/// Label above the field (13/500, textSecondary). Height comes from
/// [AppSizing]: 40 on desktop, 48 on mobile.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    this.value = '',
    this.placeholder,
    this.obscure = false,
    this.trailing,
    this.state = AppTextFieldState.normal,
    this.errorText,
    this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final String? placeholder;
  final bool obscure;
  final Widget? trailing;
  final AppTextFieldState state;

  /// Shown below the field when [state] is [AppTextFieldState.error].
  final String? errorText;

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final height = isTouchPlatform(context)
        ? AppSizing.fieldMobile
        : AppSizing.fieldDesktop;

    // The focused ring uses primaryAccent, not primaryAction. A border is
    // NON-TEXT (3:1 floor), and after the T3 ramp shift primaryAction measures
    // only 2.91:1 against the dark surface — it fails even 3:1 there.
    // primaryAccent (#158A76) measures 4.26:1 light / 3.88:1 dark, passing in
    // both. This is the use RULING 2 retained primaryAccent for.
    final (borderColour, borderWidth) = switch (state) {
      AppTextFieldState.normal => (t.border, AppSizing.borderThin),
      AppTextFieldState.focused => (t.primaryAccent, AppSizing.borderThick),
      AppTextFieldState.error => (t.danger, AppSizing.borderThick),
      AppTextFieldState.disabled => (t.border, AppSizing.borderThin),
    };

    final disabled = state == AppTextFieldState.disabled;
    final hasValue = value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.fieldLabel.copyWith(
            color: disabled ? t.textDisabled : t.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
          decoration: BoxDecoration(
            color: disabled ? t.surfaceSunken : t.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: borderColour, width: borderWidth),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasValue
                      ? (obscure ? '•' * value.length : value)
                      : (placeholder ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyTeacher.copyWith(
                    color: disabled
                        ? t.textDisabled
                        : hasValue
                            ? t.textPrimary
                            : t.textMuted,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.space3),
                trailing!,
              ],
            ],
          ),
        ),
        if (state == AppTextFieldState.error && errorText != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            errorText!,
            style: AppTypography.fieldLabel.copyWith(color: t.danger),
          ),
        ],
      ],
    );
  }
}

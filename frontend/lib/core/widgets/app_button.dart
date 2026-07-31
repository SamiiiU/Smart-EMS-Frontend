import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum AppButtonVariant { primary, secondary, ghost }

enum AppButtonSize { sm, md, lg }

/// True when the touch-target NFR applies: a finger, not a pointer.
bool isTouchPlatform(BuildContext context) {
  return switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

extension AppButtonSizeHeight on AppButtonSize {
  double get baseHeight => switch (this) {
        AppButtonSize.sm => AppSizing.buttonSm,
        AppButtonSize.md => AppSizing.buttonMd,
        AppButtonSize.lg => AppSizing.buttonLg,
      };

  /// The height actually rendered. On touch platforms this is raised to
  /// [AppSizing.touchTargetMin] so the Phase 0 NFR holds — which means [sm]
  /// collapses to the same height as [md] on mobile, by design.
  double heightFor({required bool touch}) =>
      touch ? math.max(baseHeight, AppSizing.touchTargetMin) : baseHeight;
}

class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.fullWidth = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool fullWidth;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onPressed != null;
    final touch = isTouchPlatform(context);
    final height = widget.size.heightFor(touch: touch);

    final Color fill;
    final Color fg;
    final Color? borderColour;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        // Only the filled variant gets a filled disabled state.
        fill = !enabled
            ? t.surfaceSunken
            : _pressed
                ? t.primaryPressed
                : t.primaryAction;
        fg = t.onPrimary;
        borderColour = null;
      case AppButtonVariant.secondary:
        // Stays outlined when disabled — a grey fill would read as primary.
        fill = enabled && _pressed
            ? t.primarySubtle
            : SmartEmsTokens.transparent;
        // Two-tone by design, not by compromise (D-35):
        //  - LABEL  primaryTextOnSurface — primary-coloured TEXT on a surface,
        //    so it remaps between modes (RULING 3.1 / D-32).
        //  - BORDER primaryAccent — non-text, 3:1 floor. primaryAction
        //    measures only 2.91:1 against the dark surface, and because this
        //    variant has NO FILL the border is the control's only boundary:
        //    at 2.91 the label is legible but the button's extent is not.
        //    primaryAccent gives 3.88:1 (D-35, superseding the "do not change
        //    borders" clause of RULING 3.1).
        // In both modes the label reads more prominently than the border,
        // which is the correct relationship — text ahead of its container edge.
        fg = t.primaryTextOnSurface;
        borderColour = enabled ? t.primaryAccent : t.border;
      case AppButtonVariant.ghost:
        // Text only, always — including when disabled.
        fill = enabled && _pressed
            ? t.primarySubtle
            : SmartEmsTokens.transparent;
        fg = t.primaryTextOnSurface;
        borderColour = null;
    }

    final textStyle = switch (widget.size) {
      AppButtonSize.sm => AppTypography.fieldLabel,
      AppButtonSize.md => AppTypography.personName,
      AppButtonSize.lg => AppTypography.personName,
    };

    final content = Row(
      mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(
            widget.icon,
            size: AppSpacing.space6,
            color: enabled ? fg : t.textDisabled,
          ),
          const SizedBox(width: AppSpacing.space3),
        ],
        Text(
          widget.label,
          style: textStyle.copyWith(color: enabled ? fg : t.textDisabled),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Container(
          height: height,
          width: widget.fullWidth ? double.infinity : null,
          constraints: const BoxConstraints(
            minWidth: AppSizing.touchTargetMin,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: borderColour == null
                ? null
                : Border.all(
                    color: borderColour,
                    width: AppSizing.borderThin,
                  ),
          ),
          // No Center() here: Center expands to the incoming max width, which
          // made every button full-width inside a Wrap. Container.alignment
          // centres the child without forcing the box to grow.
          child: content,
        ),
      ),
    );
  }
}

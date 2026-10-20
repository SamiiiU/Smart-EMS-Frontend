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
    this.semanticsLabel,
    this.semanticsHint,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool fullWidth;

  /// Optional fuller accessible name when [label] alone is ambiguous, e.g.
  /// "Approve, Ayesha Khan" for a row action. Defaults to [label].
  final String? semanticsLabel;

  /// Optional accessible hint, e.g. why the button is disabled.
  final String? semanticsHint;

  /// Take keyboard focus when first shown (e.g. the safe choice in a
  /// confirmation dialog, so focus moves into the dialog on web too).
  final bool autofocus;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  /// True only while focus arrived by keyboard (Flutter's focus-highlight
  /// mode), so a mouse click or a tap never leaves a ring behind.
  bool _focusHighlight = false;

  /// Mirrors keyboard focus into semantics (see build).
  bool _hasFocus = false;

  void _activate() => widget.onPressed?.call();

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
        // Flexible + ellipsis so a long label DEGRADES instead of
        // overflowing. Found in T8: 'Submit attendance' on a full-width
        // button overflowed by 2.4px at a 2x text scale on a 360px phone —
        // the button height is fixed by AppSizing, so the label cannot wrap,
        // and without this it renders the yellow overflow stripes to a user
        // who has merely turned text size up. Prefer a shorter label; this
        // is the safety net, not a licence for long ones.
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textStyle.copyWith(color: enabled ? fg : t.textDisabled),
          ),
        ),
      ],
    );

    return Semantics(
      // Release blocker (Academy B5 a11y, reports 07/09): without its own
      // container this node MERGED into the nearest ancestor node — a table
      // row or a card — so assistive technology got a row/card-sized "button"
      // (unnamed in Chromium) and a click at its centre missed the control.
      // A container keeps the name, flags and bounds on the button itself.
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label,
      hint: widget.semanticsHint,
      // Excluding child semantics also drops the focus flags of the detector
      // below, and Flutter Web only makes focusable nodes DOM tab stops: so
      // they are declared here, or the browser skips every AppButton on Tab.
      focusable: enabled ? true : null,
      focused: enabled ? _hasFocus : null,
      // F6: the visible text would otherwise merge in and read the name twice
      // ("Sign in Sign in" in Chromium's accessibility tree).
      excludeSemantics: true,
      // Child semantics (including the gesture's tap action) are excluded, so
      // the activation action is declared here explicitly.
      onTap: widget.onPressed,
      // Keyboard (M1 accessibility finding): the GestureDetector alone created
      // no focus node, so no AppButton could be reached with Tab or run with
      // Enter/Space. FocusableActionDetector is the standard Flutter primitive
      // Material buttons use for this; disabled = not focusable. Both intents
      // are handled because web maps Enter to ButtonActivateIntent.
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        enabled: enabled,
        onFocusChange: (v) => setState(() => _hasFocus = v),
        onShowFocusHighlight: (v) => setState(() => _focusHighlight = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          // Foreground ring: drawn over the button, so size, padding and layout
          // are unchanged. primaryAccent meets the 3:1 non-text contrast floor
          // in both themes (D-35).
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: enabled && _focusHighlight
                  ? Border.all(
                      color: t.primaryAccent,
                      width: 2,
                      // Outside the edge: visible on the filled primary
                      // variant too, and still no layout change.
                      strokeAlign: BorderSide.strokeAlignOutside,
                    )
                  : null,
            ),
            child: Container(
              height: height,
              width: widget.fullWidth ? double.infinity : null,
              constraints: const BoxConstraints(
                minWidth: AppSizing.touchTargetMin,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space6,
              ),
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
        ),
      ),
    );
  }
}

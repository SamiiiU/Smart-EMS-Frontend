import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A custom-drawn tap target (navigation item, icon toggle) that is also fully
/// keyboard-operable — the same mechanism as [AppButton] (accessibility
/// findings A11Y-1/2/3), for controls whose visuals are not a button.
///
/// - Reachable with Tab / Shift+Tab; Enter and Space activate it.
/// - One semantics node: [label] (+ [selected] for navigation), marked
///   focusable so Flutter Web gives it a DOM tab stop. Child semantics are
///   excluded, so icon and text are never announced separately.
/// - A 2 px [SmartEmsTokens.primaryAccent] ring for keyboard focus only (never
///   after a tap); drawn as a foreground decoration, so layout is unchanged.
/// - Disabled ([enabled] false or [onTap] null): not focusable, not tappable.
///
/// Visibility is NOT authorization: hiding a destination is a convenience; the
/// server enforces every permission.
class KeyboardTapTarget extends StatefulWidget {
  const KeyboardTapTarget({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
    this.toggled,
    this.enabled = true,
    this.borderRadius = 8,
    this.ringOutside = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  /// For navigation destinations: announced as the current/selected item.
  final bool? selected;

  /// For on/off controls (e.g. Absent): announced as a toggle with its state.
  final bool? toggled;
  final bool enabled;
  final double borderRadius;

  /// Draw the ring outside the edge (for small icon targets, where an inside
  /// ring would cover the icon). Inside by default, so rows in clipped lists
  /// such as the sidebar keep their ring visible.
  final bool ringOutside;

  @override
  State<KeyboardTapTarget> createState() => _KeyboardTapTargetState();
}

class _KeyboardTapTargetState extends State<KeyboardTapTarget> {
  bool _hasFocus = false;
  bool _highlight = false;

  bool get _enabled => widget.enabled && widget.onTap != null;

  void _activate() {
    if (_enabled) widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = _enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      toggled: widget.toggled,
      label: widget.label,
      excludeSemantics: true,
      focusable: enabled ? true : null,
      focused: enabled ? _hasFocus : null,
      onTap: enabled ? widget.onTap : null,
      child: FocusableActionDetector(
        enabled: enabled,
        onFocusChange: (v) => setState(() => _hasFocus = v),
        onShowFocusHighlight: (v) => setState(() => _highlight = v),
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
          onTap: enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: enabled && _highlight
                  ? Border.all(
                      color: t.primaryAccent,
                      width: 2,
                      strokeAlign: widget.ringOutside
                          ? BorderSide.strokeAlignOutside
                          : BorderSide.strokeAlignInside,
                    )
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

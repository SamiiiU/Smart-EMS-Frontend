import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import 'app_button.dart' show isTouchPlatform;

enum AppTextFieldState { normal, focused, error, disabled }

/// Label above the field (13/500, textSecondary). Height comes from
/// [AppSizing]: 40 on desktop, 48 on mobile.
///
/// **This is a real text input.** It was originally built (T2) as a
/// display-only mock — it rendered `Text(value)` with no [EditableText], no
/// focus handling, and an [onChanged] that was declared but never wired to
/// anything, so it could not fire. That went unnoticed until T7 needed the
/// first actual form. It now wraps a [TextField]; the visual contract, the
/// public API and every token used are unchanged.
///
/// Controlled component: [value] is the source of truth and [onChanged]
/// reports edits. The internal controller is re-synced only when [value]
/// actually differs from what is typed, so a parent rebuild mid-typing does
/// not clobber the cursor.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    this.value = '',
    this.placeholder,
    this.obscure = false,
    this.trailing,
    this.trailingTouchTarget = false,
    this.state = AppTextFieldState.normal,
    this.errorText,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.required = false,
    this.keyboardType,
    super.key,
  });

  final String label;
  final String value;

  /// Optional platform keyboard (e.g. decimal amounts). Null keeps the default.
  final TextInputType? keyboardType;
  final String? placeholder;
  final bool obscure;
  final Widget? trailing;

  /// Lay [trailing] out as a full-height, [trailingTargetWidth]-wide hit area
  /// at the field's right edge (over the border), instead of an icon-sized box
  /// inside the padding. Gives an icon toggle a 48 x 48 touch target on touch
  /// platforms (field height 48) while the icon itself keeps its size and
  /// (to within 2 px) its position. Opt-in, so other trailing widgets are
  /// unchanged.
  final bool trailingTouchTarget;

  /// Width of the [trailingTouchTarget] hit area.
  static const double trailingTargetWidth = 48;

  /// Supply one to drive focus from outside — e.g. moving field-to-field on
  /// the keyboard's "next". When null the field owns its own node, which is
  /// what every pre-existing call site does.
  final FocusNode? focusNode;

  final bool autofocus;

  /// `next` on all but the last field, `done` on the last.
  final TextInputAction? textInputAction;

  /// Fired on "next"/"done"/Enter. Distinct from [onChanged] so a caller can
  /// advance focus or submit without inspecting keystrokes.
  final ValueChanged<String>? onSubmitted;

  /// An EXPLICIT state override. [AppTextFieldState.normal] (the default)
  /// lets the field derive its own focused/unfocused appearance from real
  /// focus; anything else wins over that, so a caller can still force the
  /// error or disabled treatment.
  final AppTextFieldState state;

  /// Shown below the field when the effective state is
  /// [AppTextFieldState.error].
  final String? errorText;

  final ValueChanged<String>? onChanged;

  /// Announced to assistive technology ("Required"); the visual design is unchanged.
  final bool required;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// True when this widget created the node and must therefore dispose it.
  /// Disposing a caller-owned node would break the next field to use it.
  late final bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = (widget.focusNode ?? FocusNode())
      ..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    // Only dispose a node we created — disposing a caller-owned one would
    // break whatever else still holds it.
    if (_ownsFocusNode) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// An explicit non-normal [AppTextField.state] wins; otherwise real focus
  /// decides. Without this, the focus ring would be a lie on a field the
  /// user is actually typing into.
  AppTextFieldState get _effectiveState {
    if (widget.state != AppTextFieldState.normal) return widget.state;
    return _focusNode.hasFocus
        ? AppTextFieldState.focused
        : AppTextFieldState.normal;
  }

  String? _semanticHint(AppTextFieldState state) {
    final parts = [
      if (widget.required) 'Required',
      if (state == AppTextFieldState.error && widget.errorText != null)
        widget.errorText!,
    ];
    return parts.isEmpty ? null : parts.join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = _effectiveState;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // F6: the visible label is decorative for assistive technology; the
        // input itself carries the accessible name (no duplicate reading).
        ExcludeSemantics(
          child: Text(
            widget.label,
            style: AppTypography.fieldLabel.copyWith(
              color: disabled ? t.textDisabled : t.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Stack(
          children: [
            Container(
              height: height,
              padding: EdgeInsets.only(
                left: AppSpacing.space5,
                right: widget.trailingTouchTarget && widget.trailing != null
                    ? AppTextField.trailingTargetWidth
                    : AppSpacing.space5,
              ),
              decoration: BoxDecoration(
                color: disabled ? t.surfaceSunken : t.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: borderColour, width: borderWidth),
              ),
              child: Row(
                children: [
                  Expanded(
                    // DEF-16: its own node, so nearby headings and help text are not
                    // merged into the field's accessible name.
                    child: Semantics(
                      container: true,
                      label: widget.label,
                      hint: _semanticHint(state),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !disabled,
                        obscureText: widget.obscure,
                        keyboardType: widget.keyboardType,
                        onChanged: widget.onChanged,
                        autofocus: widget.autofocus,
                        textInputAction: widget.textInputAction,
                        onSubmitted: widget.onSubmitted,
                        maxLines: 1,
                        cursorColor: t.primaryAccent,
                        style: AppTypography.bodyTeacher.copyWith(
                          color: disabled ? t.textDisabled : t.textPrimary,
                        ),
                        // `collapsed` strips Material's own padding, underline and
                        // 48px min height, so the surrounding Container remains the
                        // single source of the field's geometry — the same box the
                        // display-only version drew.
                        decoration: InputDecoration.collapsed(
                          hintText: widget.placeholder ?? '',
                          hintStyle: AppTypography.bodyTeacher.copyWith(
                            color: disabled ? t.textDisabled : t.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.trailing != null &&
                      !widget.trailingTouchTarget) ...[
                    const SizedBox(width: AppSpacing.space3),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
            if (widget.trailing != null && widget.trailingTouchTarget)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: AppTextField.trailingTargetWidth,
                child: widget.trailing!,
              ),
          ],
        ),
        if (state == AppTextFieldState.error && widget.errorText != null) ...[
          const SizedBox(height: AppSpacing.space2),
          // Announced when it appears, so a screen-reader user hears the error.
          Semantics(
            liveRegion: true,
            child: Text(
              widget.errorText!,
              style: AppTypography.fieldLabel.copyWith(color: t.danger),
            ),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/widgets.dart';

import '../theme/motion.dart';

/// An arrival: a one-shot fade, optionally with a small rise or scale.
///
/// This is the single place expressive entrance motion is implemented, so
/// D-29's rules hold everywhere by construction rather than by everyone
/// remembering them:
///
/// - **compositor only (D-05)** — it drives `Opacity` and `Transform`, never
///   a size or a padding, so no frame costs a layout pass;
/// - **one-shot, never looping (D-29)** — it runs once on mount and stops.
///   There is deliberately no `repeat` and no `reverse`;
/// - **reduced motion is honoured** — under it the travel and the scale are
///   dropped and the opacity fade remains, which is exactly what D-29 asks
///   for. Not optional, and not a setting.
///
/// It is for ARRIVAL. It is not for tab switching, which D-29 prohibits
/// outright: a surface switched dozens of times a day should be instant.
class MotionReveal extends StatefulWidget {
  const MotionReveal({
    required this.child,
    this.duration = AppMotion.sectionReveal,
    this.delay = Duration.zero,
    this.curve = AppMotion.expressiveEntrance,
    this.offset = AppMotion.revealOffset,
    this.scaleFrom,
    super.key,
  });

  /// A staggered sibling: index [index] of a group, using D-29's 60ms step.
  MotionReveal.staggered({
    required this.child,
    required int index,
    this.duration = AppMotion.sectionReveal,
    this.curve = AppMotion.expressiveEntrance,
    this.offset = AppMotion.revealOffset,
    this.scaleFrom,
    super.key,
  }) : delay = AppMotion.staggerFor(index);

  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  /// Vertical travel. Zero for a pure fade.
  final double offset;

  /// Scale to grow from, or null for no scale. Only the parent status hero
  /// uses this (D-29).
  final double? scaleFrom;

  @override
  State<MotionReveal> createState() => _MotionRevealState();
}

class _MotionRevealState extends State<MotionReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Eager, for the same reason as MotionConfirm: a lazily-initialised
    // controller can end up constructed during dispose.
    _controller = AnimationController(duration: widget.duration, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (AppMotion.reduced(context)) {
      // Reduced motion still FADES — D-29 keeps opacity. Jumping straight to
      // 1 here would be the other failure: content appearing with a snap.
      _controller.duration = widget.duration;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final curved = CurvedAnimation(
      parent: _controller,
      // A reduced-motion fade uses the functional curve: the expressive one
      // exists to give travel its character, and there is no travel here.
      curve: reduced ? AppMotion.functionalEase : widget.curve,
    );

    return AnimatedBuilder(
      animation: curved,
      // Built once and reused — the subtree does not rebuild per frame, only
      // the Opacity and Transform wrapping it.
      child: widget.child,
      builder: (context, child) {
        final t = curved.value;
        Widget result = Opacity(opacity: t, child: child);

        if (reduced) return result;

        if (widget.scaleFrom != null) {
          final scale = widget.scaleFrom! + (1 - widget.scaleFrom!) * t;
          result = Transform.scale(scale: scale, child: result);
        }
        if (widget.offset != 0) {
          result = Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: result,
          );
        }
        return result;
      },
    );
  }
}

/// The submit-confirmation settle — the **only** overshoot in the product
/// (D-29).
///
/// Plays once when [show] turns true. Kept separate from [MotionReveal] so
/// that [AppMotion.expressiveSettle] has exactly one call site and cannot
/// quietly spread: a bouncy product is precisely what D-29 avoids.
class MotionConfirm extends StatefulWidget {
  const MotionConfirm({required this.show, required this.child, super.key});

  final bool show;
  final Widget child;

  @override
  State<MotionConfirm> createState() => _MotionConfirmState();
}

class _MotionConfirmState extends State<MotionConfirm>
    with SingleTickerProviderStateMixin {
  /// Created eagerly, NOT as a lazy `late final`.
  ///
  /// A lazy field that is only touched when the confirmation actually plays
  /// would first be initialised inside `dispose()` — constructing a ticker
  /// against a deactivated element, which throws "Looking up a deactivated
  /// widget's ancestor is unsafe". Caught by the test that mounts this with
  /// `show: false` and never shows it.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppMotion.confirmation,
      vsync: this,
    );
    if (widget.show) _controller.forward();
  }

  @override
  void didUpdateWidget(MotionConfirm old) {
    super.didUpdateWidget(old);
    if (widget.show && !old.show) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return const SizedBox.shrink();

    final reduced = AppMotion.reduced(context);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: reduced ? AppMotion.functionalEase : AppMotion.expressiveSettle,
    );

    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        final t = curved.value;
        final faded = Opacity(opacity: t.clamp(0.0, 1.0), child: child);
        // The overshoot lives in the curve, so the scale simply follows it —
        // `expressiveSettle` passes 1 and comes back.
        return reduced ? faded : Transform.scale(scale: t, child: faded);
      },
    );
  }
}

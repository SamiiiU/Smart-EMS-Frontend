import 'package:flutter/widgets.dart';

/// Motion tokens — the implementation of D-03, D-04, D-05 and D-29.
///
/// Every duration and curve here is transcribed from D-29, which was decided
/// with the visuals and never built. Nothing in this file is invented; if a
/// moment is not listed in D-29, it does not get expressive motion.
///
/// ## The three rules that constrain everything below
///
/// - **D-04 — the budget scales inversely with screen frequency.** A 300ms
///   transition on a row tapped 40 times is 12 seconds of a 90-second task.
///   High-frequency screens get [fast]/[functional] and nothing expressive;
///   low-frequency, once-per-session moments may spend 250–400ms.
/// - **D-05 — compositor only.** Animate `transform` and `opacity`. Never
///   width, height, top or left: they force layout on every frame and are
///   visibly janky on the budget Android this product targets. That rules
///   out `AnimatedSize` and animated padding, however convenient.
/// - **D-29 — expressive motion is confined to reward and arrival moments**,
///   and is **prohibited** on tab switching (switched dozens of times a day —
///   instant is correct), on anything looping or idle (battery), in empty
///   state illustrations (asset weight), and as parallax.
///
/// ## Reduced motion is an accessibility requirement, not an option
///
/// Under `prefers-reduced-motion` the expressive part goes away — no scale,
/// no travel — and an **opacity fade remains**. Use [reduced] to branch, or
/// better, use `MotionReveal`, which already does.
abstract final class AppMotion {
  // --- D-04 functional band (high-frequency screens) -------------------------

  /// 120ms — the floor of the functional band. Selection feedback, anything
  /// on a screen the user touches repeatedly.
  static const Duration fast = Duration(milliseconds: 120);

  /// 180ms — the ceiling of the functional band.
  static const Duration functional = Duration(milliseconds: 180);

  // --- D-29 expressive moments, verbatim -------------------------------------

  /// Login entry. Once per session, so it can afford the most.
  static const Duration loginEntry = Duration(milliseconds: 400);

  /// Parent status hero reveal — with [heroScaleFrom]. The one thing they
  /// opened the app for: it should RESOLVE, not appear.
  static const Duration heroReveal = Duration(milliseconds: 300);

  /// Onboarding checklist tick.
  static const Duration checklistTick = Duration(milliseconds: 300);

  /// Dashboard KPI arrival. The stagger is honest — each KPI loads from its
  /// own endpoint, so simultaneous arrival would misrepresent that.
  static const Duration kpiReveal = Duration(milliseconds: 250);

  /// Section reveal, staggered.
  static const Duration sectionReveal = Duration(milliseconds: 200);

  /// Submit confirmation, then settle. The only overshoot in the product.
  static const Duration confirmation = Duration(milliseconds: 250);

  /// Empty state entrance.
  static const Duration emptyStateEntrance = Duration(milliseconds: 250);

  /// The gap between staggered siblings.
  static const Duration staggerStep = Duration(milliseconds: 60);

  /// One shimmer sweep on a loading skeleton.
  ///
  /// ⚠️ The **only** looping animation in the product, and the single
  /// documented exception to D-29's ban (D-T4-05): D-29 prohibits *idle*
  /// animation — motion with nothing behind it — and a shimmer communicates
  /// active work. It is opacity-only, it stops the moment data arrives, and
  /// under reduced motion it stops entirely, leaving a STATIC skeleton
  /// rather than none. Do not add a second looping animation on the
  /// strength of this one.
  static const Duration shimmerPeriod = Duration(milliseconds: 900);

  /// How far a staggered list is allowed to run before later items stop
  /// waiting. Without a cap, item 40 of a roster would start 2.4s in — the
  /// screen would look broken rather than considered.
  static const int maxStaggeredItems = 6;

  // --- Curves ----------------------------------------------------------------

  /// Functional motion: plain ease-out.
  static const Curve functionalEase = Curves.easeOut;

  /// Expressive entrance — `cubic-bezier(.2,.9,.3,1)`.
  static const Curve expressiveEntrance = Cubic(0.2, 0.9, 0.3, 1);

  /// Expressive settle — `cubic-bezier(.2,1.3,.4,1)`. **Overshoots**, and is
  /// for submit confirmation ONLY. Using it elsewhere makes the product feel
  /// bouncy, which D-29 deliberately avoids.
  static const Curve expressiveSettle = Cubic(0.2, 1.3, 0.4, 1);

  // --- Transforms ------------------------------------------------------------

  /// The parent hero scales from this to 1. Small on purpose: it should read
  /// as resolving, not as zooming.
  static const double heroScaleFrom = 0.97;

  /// Vertical travel for an arrival, in logical pixels. A `transform`, never
  /// a layout change (D-05).
  static const double revealOffset = 8;

  /// Whether the platform has asked for reduced motion.
  ///
  /// Honoured everywhere expressive motion appears. Under it, scale and
  /// travel are dropped and only the opacity fade remains.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The delay for item [index] in a staggered group, capped by
  /// [maxStaggeredItems].
  static Duration staggerFor(int index) => Duration(
        milliseconds: staggerStep.inMilliseconds *
            (index < maxStaggeredItems ? index : maxStaggeredItems),
      );
}

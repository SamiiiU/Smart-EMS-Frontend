import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/scales.dart';
import '../../theme/sizing.dart';

/// Which shape the skeleton stands in for. Each variant's dimensions match the
/// real component it replaces, so nothing shifts when data arrives.
enum SkeletonVariant { listRows, cards, tableRows, statCards }

/// Skeleton placeholders — never a spinner.
///
/// DIMENSIONS MUST MATCH THE REAL CONTENT. A 56px skeleton row replacing a 56px
/// [ListRow] means nothing moves on load. A generic block that resizes when
/// data arrives is a layout jump, and that reads worse than no skeleton at all.
/// A test asserts the list-row height against [AppSizing.listRowMinHeight].
///
/// SHIMMER IS PERMITTED HERE — the one exception to D-29's ban on looping
/// animation. D-29 prohibits *idle* animation: motion with nothing behind it.
/// A shimmer communicates active work, and a fully static skeleton reads as
/// stuck. Constraints, all enforced below:
///  - opacity only, never layout (D-05);
///  - stops the instant data arrives (the widget is removed by the precedence
///    rule, so the ticker is disposed with it);
///  - stops immediately under `prefers-reduced-motion`, leaving a STATIC
///    skeleton rather than no skeleton.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    required this.variant,
    this.count = 5,
    super.key,
  }) : assert(count > 0, 'a skeleton with no rows communicates nothing');

  const LoadingSkeleton.listRows({int count = 5, Key? key})
      : this(variant: SkeletonVariant.listRows, count: count, key: key);

  const LoadingSkeleton.cards({int count = 3, Key? key})
      : this(variant: SkeletonVariant.cards, count: count, key: key);

  const LoadingSkeleton.tableRows({int count = 5, Key? key})
      : this(variant: SkeletonVariant.tableRows, count: count, key: key);

  const LoadingSkeleton.statCards({int count = 4, Key? key})
      : this(variant: SkeletonVariant.statCards, count: count, key: key);

  final SkeletonVariant variant;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      // The shapes are decoration; only the "Loading" label should be read.
      child: ExcludeSemantics(
        child: _Shimmer(
          child: switch (variant) {
            SkeletonVariant.listRows => _ListRowSkeletons(count: count),
            SkeletonVariant.cards => _CardSkeletons(count: count),
            SkeletonVariant.tableRows => _TableRowSkeletons(count: count),
            SkeletonVariant.statCards => _StatCardSkeletons(count: count),
          },
        ),
      ),
    );
  }
}

/// Opacity-only pulse (D-05: compositor properties only — no width/height).
///
/// Under `MediaQuery.disableAnimations` the ticker is never started and the
/// child renders at full opacity, so the skeleton is static but still present.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  /// Created eagerly in [initState], NOT as a lazy `late final`.
  ///
  /// A lazy initialiser is a real bug here: under reduced motion nothing ever
  /// touches the controller, so the first access is `dispose()` — which would
  /// construct an `AnimationController` during unmount and perform a
  /// `TickerMode` ancestor lookup on a deactivated element. That throws
  /// "Looking up a deactivated widget's ancestor is unsafe", in production as
  /// well as in tests, for exactly the users who asked for less motion.
  late final AnimationController _controller;

  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
  }

  /// Cached in [didChangeDependencies] rather than read in [build]. Reading an
  /// inherited widget during build means the lookup can happen while the
  /// element is being deactivated, which throws "Looking up a deactivated
  /// widget's ancestor is unsafe" during teardown.
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _running) {
      _controller
        ..stop()
        ..value = 1;
      _running = false;
    } else if (!_reduceMotion && !_running) {
      _controller.repeat(reverse: true);
      _running = true;
    }
  }

  @override
  void dispose() {
    // Stops the shimmer for good — the precedence rule removes this widget the
    // instant data arrives, so disposal is also "stop on data".
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      // Static skeleton — present, but not animated. An accessibility
      // requirement, not an option (D-29).
      return widget.child;
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

/// A single neutral block. The only shape any skeleton is built from.
class _Block extends StatelessWidget {
  const _Block({
    required this.height,
    this.width,
    this.circle = false,
  });

  final double height;
  final double? width;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

/// The inner content of one list-row skeleton. Extracted so it can be a single
/// `const` subtree — cheaper to rebuild, and it keeps the builders readable.
class _ListRowSkeletonContent extends StatelessWidget {
  const _ListRowSkeletonContent();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Block(
          height: AppSizing.avatar40,
          width: AppSizing.avatar40,
          circle: true,
        ),
        SizedBox(width: AppSpacing.space5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Block(height: AppSpacing.space5),
              SizedBox(height: AppSpacing.space2),
              FractionallySizedBox(
                widthFactor: 0.6,
                child: _Block(height: AppSpacing.space4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Matches [ListRow]: 56px minimum height, avatar-sized leading circle, two
/// text lines. The height match is what prevents a layout jump on load.
class _ListRowSkeletons extends StatelessWidget {
  const _ListRowSkeletons({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            // Exactly the real row's minimum height.
            constraints: const BoxConstraints(
              minHeight: AppSizing.listRowMinHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space4,
            ),
            child: const _ListRowSkeletonContent(),
          ),
      ],
    );
  }
}

class _CardSkeletonContent extends StatelessWidget {
  const _CardSkeletonContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FractionallySizedBox(
          widthFactor: 0.45,
          child: _Block(height: AppSpacing.space6),
        ),
        SizedBox(height: AppSpacing.space5),
        _Block(height: AppSpacing.space4),
        SizedBox(height: AppSpacing.space3),
        FractionallySizedBox(
          widthFactor: 0.8,
          child: _Block(height: AppSpacing.space4),
        ),
      ],
    );
  }
}

/// Matches a [SectionCard] with a header and a couple of body lines.
class _CardSkeletons extends StatelessWidget {
  const _CardSkeletons({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.space5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.space6),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: t.border, width: AppSizing.borderThin),
            ),
            child: const _CardSkeletonContent(),
          ),
        ],
      ],
    );
  }
}

/// Three evenly-spaced blocks, standing in for a table row or header band.
class _ColumnsRow extends StatelessWidget {
  const _ColumnsRow({required this.blockHeight});

  final double blockHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var c = 0; c < 3; c++) ...[
          if (c > 0) const SizedBox(width: AppSpacing.space5),
          Expanded(child: _Block(height: blockHeight)),
        ],
      ],
    );
  }
}

/// Matches [AppDataTable]: a sunken header band, then rows at the same minimum
/// height as the real ones.
class _TableRowSkeletons extends StatelessWidget {
  const _TableRowSkeletons({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: t.surfaceSunken,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space5,
            vertical: AppSpacing.space4,
          ),
          child: const _ColumnsRow(blockHeight: AppSpacing.space4),
        ),
        for (var i = 0; i < count; i++)
          Container(
            constraints: const BoxConstraints(
              minHeight: AppSizing.listRowMinHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space4,
            ),
            child: const _ColumnsRow(blockHeight: AppSpacing.space5),
          ),
      ],
    );
  }
}

class _StatCardSkeletonContent extends StatelessWidget {
  const _StatCardSkeletonContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FractionallySizedBox(
          widthFactor: 0.6,
          child: _Block(height: AppSpacing.space8),
        ),
        SizedBox(height: AppSpacing.space3),
        _Block(height: AppSpacing.space4),
      ],
    );
  }
}

/// Matches a row of [StatCard]s.
class _StatCardSkeletons extends StatelessWidget {
  const _StatCardSkeletons({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Wrap(
      spacing: AppSpacing.space4,
      runSpacing: AppSpacing.space4,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: AppSizing.statCardSkeletonWidth,
            padding: const EdgeInsets.all(AppSpacing.space5),
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const _StatCardSkeletonContent(),
          ),
      ],
    );
  }
}

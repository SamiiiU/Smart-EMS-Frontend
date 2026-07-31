import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';

/// 8px tall, fully rounded. Track `surfaceSunken`, fill chosen by threshold.
///
/// Used for attendance percentage and for import progress.
///
/// THRESHOLD: `>= 75` renders `success`, `< 75` renders `warning`. This is the
/// only documented threshold, and it is deliberately the only one — the
/// below-75% treatment appears on parent landing, parent calendar, admin
/// profile, and the student's own screen, and must read identically in all
/// four. There is no third "danger" tier.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    required this.percent,
    super.key,
  }) : assert(percent >= 0 && percent <= 100, 'percent must be 0..100');

  /// 0..100.
  final double percent;

  /// The single documented threshold.
  static const double successThreshold = 75;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = percent >= successThreshold ? t.success : t.warning;

    return Semantics(
      value: '${percent.toStringAsFixed(0)}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          height: AppSizing.progressBarHeight,
          color: t.surfaceSunken,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (percent / 100).clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: const SizedBox(
                height: AppSizing.progressBarHeight,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

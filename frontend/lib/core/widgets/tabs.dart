import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// One tab. [hasContent] is what implements D-19.
class AppTab {
  const AppTab({
    required this.label,
    this.hasContent = true,
  });

  final String label;

  /// D-19: a tab appears only when its content exists. Pass false and the tab
  /// is not rendered at all — it is NOT rendered greyed out or empty.
  final bool hasContent;
}

/// Underline tabs with a `primaryAccent` indicator.
///
/// Used on the student profile and CSV import.
///
/// D-19 IS ENFORCED HERE: tabs whose `hasContent` is false are filtered out
/// before rendering, so an empty tab never appears. [selectedIndex] and
/// [onSelected] index into the VISIBLE tabs, so callers cannot accidentally
/// select a hidden one.
///
/// The indicator uses `primaryAccent`, not `primaryAction`: an underline is
/// non-text (3:1 floor) and after the T3 ramp shift `primaryAction` measures
/// only 2.91:1 against the dark surface, failing even 3:1.
class Tabs extends StatelessWidget {
  const Tabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<AppTab> tabs;

  /// Index into the VISIBLE tabs.
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// The tabs that will actually render, after the D-19 filter.
  static List<AppTab> visible(List<AppTab> all) =>
      all.where((t) => t.hasContent).toList();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = visible(tabs);

    if (shown.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.border, width: AppSizing.borderThin),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < shown.length; i++)
            _TabItem(
              label: shown[i].label,
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizing.touchTargetMin,
            minWidth: AppSizing.touchTargetMin,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space5,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? t.primaryAccent : SmartEmsTokens.transparent,
                width: AppSizing.tabIndicatorHeight,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.fieldLabel.copyWith(
              color: selected ? t.textPrimary : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

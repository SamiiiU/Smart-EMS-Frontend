import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/scales.dart';
import '../../theme/sizing.dart';
import '../../theme/typography.dart';
import '../app_button.dart';

/// Shared frame for every "nothing here" surface: centred icon, title, body,
/// optional single action. Private — each state composes it so they stay
/// visually identical without being the same component.
class StateFrame extends StatelessWidget {
  const StateFrame({
    required this.icon,
    required this.title,
    required this.message,
    required this.iconColour,
    this.action,
    this.secondary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Passed explicitly so a caller cannot accidentally give a not-an-error
  /// state a danger tint — see the OfflineState/UnlinkedProfileState tests.
  final Color iconColour;

  final Widget? action;

  /// Extra explanatory line, e.g. the escalation notice after a second
  /// consecutive retry failure.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Static icon. No animated illustration — D-29 bans them on asset
          // weight, and this product ships to low-connectivity institutions.
          Icon(icon, size: AppSizing.stateIconSize, color: iconColour),
          const SizedBox(height: AppSpacing.space6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyAdminMeta.copyWith(
              color: t.textSecondary,
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: AppSpacing.space5),
            secondary!,
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.space7),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Nothing exists yet.
///
/// The action is governed by D-19: offer one ONLY when it exists. An empty
/// student list can offer "Import students"; an empty notifications list offers
/// nothing, because there is nothing the user does about it. Passing an action
/// that does not work is the same false affordance as an enabled broken button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
          (actionLabel == null) == (onAction == null),
          'An action needs both a label and a callback (D-19). A label with no '
          'callback is a control that looks available and does nothing.',
        );

  final String title;
  final String message;
  final IconData icon;

  /// Omit BOTH when there is no real action — see D-19.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StateFrame(
      icon: icon,
      // Neutral, not semantic: an empty list is not a fault. textSecondary,
      // NOT textMuted — textMuted measures 2.39:1 on surface, below the 3:1
      // non-text floor. Same reason RULING 2.1 moved Overline off it.
      iconColour: t.textSecondary,
      title: title,
      message: message,
      action: onAction == null
          ? null
          : AppButton(label: actionLabel!, onPressed: onAction),
    );
  }
}

/// A filter matched nothing.
///
/// A SEPARATE COMPONENT, not [EmptyState] with a flag (D-14). The two say
/// different things — "there is nothing here" versus "your filter excluded
/// everything" — and conflating them is how a user concludes a record does not
/// exist when it is merely filtered out.
///
/// The clear action ALWAYS exists here, so unlike [EmptyState] it is required
/// rather than optional: a filter the user cannot clear is a trap.
class FilteredEmptyState extends StatelessWidget {
  const FilteredEmptyState({
    required this.filterDescription,
    required this.onClearFilter,
    this.clearLabel = 'Clear filter',
    super.key,
  });

  /// What was filtered on, stated back to the user so they know what to change.
  final String filterDescription;

  /// Required — see the class doc.
  final VoidCallback onClearFilter;

  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StateFrame(
      icon: Icons.filter_alt_off_outlined,
      // See the note in EmptyState — textMuted fails 3:1 on surface.
      iconColour: t.textSecondary,
      title: 'No matches',
      message: 'Nothing matches $filterDescription.',
      action: AppButton(
        label: clearLabel,
        variant: AppButtonVariant.secondary,
        onPressed: onClearFilter,
      ),
    );
  }
}

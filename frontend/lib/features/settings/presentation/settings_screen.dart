import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';

/// The "More" destination (D-27's mandatory fourth tab).
///
/// Sign-out, plus the appearance choice. It exists because sign-out
/// previously lived in the desktop sidebar footer, which does not render
/// below 600px — so a phone user, which is most teachers, had no way to sign
/// out at all.
///
/// Appearance was added on request (2026-09-23): the app followed the device
/// setting only, which a person on a device set to light mode cannot
/// override, however dim the classroom.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.onSignOut,
    this.institutionCode,
    this.userLabel,
    this.themeController,
    super.key,
  });

  final Future<void> Function() onSignOut;

  /// Null in tests and anywhere the appearance section is not wanted; the
  /// section is then simply absent rather than inert.
  final ThemeController? themeController;

  /// The institution CODE, not a display name — no endpoint returns a name
  /// (see BACKEND_CONTRACT.md). Showing the code is honest.
  final String? institutionCode;
  final String? userLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More',
                style: AppTypography.screenTitle.copyWith(
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              if (userLabel != null) ...[
                Text(
                  userLabel!,
                  style: AppTypography.personName.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
              ],
              if (institutionCode != null) ...[
                Text(
                  institutionCode!,
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),
              ],
              if (themeController != null) ...[
                Text(
                  'Appearance',
                  style: AppTypography.overline.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space3),
                _ThemeChoice(controller: themeController!),
                const SizedBox(height: AppSpacing.space8),
              ],
              AppButton(
                label: 'Sign out',
                variant: AppButtonVariant.secondary,
                fullWidth: true,
                icon: Icons.logout_outlined,
                onPressed: onSignOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// System / Light / Dark, as three buttons rather than an on-off switch.
///
/// A two-state switch cannot express "follow my device", which is the
/// default and the right answer for most people — a switch would silently
/// pin the app to one mode the first time it was touched.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller,
      builder: (context, mode, _) => Wrap(
        spacing: AppSpacing.space3,
        runSpacing: AppSpacing.space3,
        children: [
          for (final (value, label, icon) in const [
            (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          ])
            _ThemeOption(
              label: label,
              icon: icon,
              selected: mode == value,
              onTap: () => controller.set(value),
            ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizing.touchTargetMin,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
            ),
            decoration: BoxDecoration(
              color: selected ? t.primarySubtle : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: selected ? t.primaryAccent : t.border,
                width: AppSizing.borderThin,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: AppSizing.avatar24,
                  color: selected ? t.textPrimary : t.textSecondary,
                ),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  label,
                  style: AppTypography.fieldLabel.copyWith(
                    color: selected ? t.textPrimary : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';
import 'sync_indicator.dart';
import 'sync_status.dart';

/// Status only — never actions (D-26).
///
/// There is NO `actions` PARAMETER. Not "actions defaults to empty" — the
/// parameter does not exist, so adding one later is a deliberate,
/// reviewable API change rather than a quiet one, mirroring how
/// `HeroCardBrand` (T3) has no `action` parameter at all.
///
/// This exists because the previous build had two overflow controls with
/// identical visual language and different destinations, and because the
/// app bar is the hardest region of the screen to reach one-handed —
/// exactly the wrong place for an action a user has to hunt for.
///
/// If a screen genuinely needs an app-bar action, that is a deviation from
/// D-26 and must be escalated as a ruling request, not added here quietly.
class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileAppBar({
    required this.institutionName,
    required this.syncStatus,
    this.hasUnreadNotifications = false,
    this.onNotificationsTap,
    this.onMenuTap,
    super.key,
  });

  /// Opens the phone navigation drawer (D-27 amendment, T16).
  ///
  /// This bar is a plain Container rather than a Material [AppBar], so
  /// Scaffold's automatic hamburger never appears — without this, a drawer
  /// could only be opened by an edge swipe, which is undiscoverable and
  /// unusable with a screen reader. Null for the roles that keep the bottom
  /// bar, and then no button renders (D-19).
  final VoidCallback? onMenuTap;

  /// School/institution name — the one piece of remembered context (D-18)
  /// shown in the shell chrome.
  final String institutionName;

  final SyncStatus syncStatus;

  final bool hasUnreadNotifications;

  /// The bell opens a NOTIFICATIONS LIST — a destination, not an action in
  /// the D-26 sense (it does not mutate anything, it navigates). Optional:
  /// omit it and no bell renders, rather than rendering a bell that does
  /// nothing (D-19).
  final VoidCallback? onNotificationsTap;

  @override
  Size get preferredSize => const Size.fromHeight(AppSizing.touchTargetMin);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          if (onMenuTap != null) ...[
            Semantics(
              button: true,
              label: 'Open navigation menu',
              child: IconButton(
                onPressed: onMenuTap,
                tooltip: 'Open navigation menu',
                icon: Icon(Icons.menu, color: t.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
          ],
          Expanded(
            child: Text(
              institutionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.cardHeading.copyWith(
                color: t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.space4),
          SyncIndicator(status: syncStatus),
          if (onNotificationsTap != null) ...[
            const SizedBox(width: AppSpacing.space2),
            _NotificationBell(
              hasUnread: hasUnreadNotifications,
              onTap: onNotificationsTap!,
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      label: hasUnread ? 'Notifications, unread' : 'Notifications',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: AppSizing.touchTargetMin,
          height: AppSizing.touchTargetMin,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.notifications_outlined,
                color: t.textSecondary,
                size: AppSpacing.space7,
              ),
              if (hasUnread)
                Positioned(
                  top: AppSpacing.space5,
                  right: AppSpacing.space5,
                  child: Container(
                    width: AppSpacing.space3,
                    height: AppSpacing.space3,
                    decoration: BoxDecoration(
                      color: t.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.surface, width: AppSizing.borderThin),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

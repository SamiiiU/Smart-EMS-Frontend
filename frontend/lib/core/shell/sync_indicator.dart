import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';
import 'sync_status.dart';

/// A labelled pill, never a bare dot. The previous build's indicator
/// rendered nothing when the connection was healthy — untestable, and
/// nobody could tell working from broken. This is ALWAYS visible, in all
/// three states.
///
/// All three states reuse token pairings already verified elsewhere in
/// `contrast_test.dart` (successBg/successTextOnBg for synced,
/// textSecondary/surfaceSunken for syncing, warningBg/warningTextOnBg for
/// offline) — no new colour pairing is introduced. `syncing` and `offline`
/// are deliberately NOT danger-toned: a slow sync and a routine offline
/// period are not faults.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({required this.status, super.key});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final (IconData icon, Color bg, Color fg, Color iconColour, String label) =
        switch (status.state) {
      SyncState.synced => (
          Icons.check_circle_outline,
          t.successBg,
          t.successTextOnBg,
          t.success,
          'Synced',
        ),
      SyncState.syncing => (
          Icons.sync,
          t.surfaceSunken,
          t.textSecondary,
          t.textSecondary,
          'Syncing…',
        ),
      SyncState.offline => (
          Icons.cloud_off_outlined,
          t.warningBg,
          t.warningTextOnBg,
          t.warning,
          status.pendingCount > 0
              ? 'Offline · ${status.pendingCount} pending'
              : 'Offline',
        ),
    };

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpacing.space6, color: iconColour),
            const SizedBox(width: AppSpacing.space2),
            Text(
              label,
              style: AppTypography.overline.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

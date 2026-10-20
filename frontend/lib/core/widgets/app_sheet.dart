import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/sizing.dart';
import '../theme/typography.dart';

/// The one bottom sheet (overhaul M1).
///
/// Every sheet gets the same frame, so users learn it once:
/// - a drag handle, a [title] announced as a heading, and a named **Close**
///   button (a sheet must be closable without a swipe gesture);
/// - capped at 90 % of the screen and scrollable, so long content and large
///   text never push the actions off-screen;
/// - lifted above the keyboard and kept inside the safe area.
/// Returns whatever the sheet pops with (null when closed).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) =>
        AppSheetFrame(title: title, child: builder(sheetContext)),
  );
}

class AppSheetFrame extends StatelessWidget {
  const AppSheetFrame({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    // Focus moves into the sheet when it opens (DLG-1 for sheets): Escape
    // closes it and Tab stays inside. Not a tab stop itself.
    return Focus(
      autofocus: true,
      skipTraversal: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space6,
                  0,
                  AppSpacing.space3,
                  AppSpacing.space3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: AppTypography.cardHeading.copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('sheet-close'),
                      tooltip: 'Close',
                      constraints: const BoxConstraints(
                        minWidth: AppSizing.touchTargetMin,
                        minHeight: AppSizing.touchTargetMin,
                      ),
                      icon: Icon(Icons.close, color: t.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

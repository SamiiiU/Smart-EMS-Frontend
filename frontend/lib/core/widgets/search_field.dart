import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/sizing.dart';
import 'app_text_field.dart';

/// The one search box (overhaul M1).
///
/// Built on [AppTextField] so labels, focus rings, error styling and text
/// scaling stay identical to every other field. What it adds:
/// - a visible, screen-reader-named **Clear** button whenever there is text
///   (recognition over recall: no "select all + delete" on a phone);
/// - [resultCount], announced politely after each change ("3 results"), so a
///   screen-reader user knows the list below changed;
/// - a search keyboard action, so Enter/Search does not insert a newline.
///
/// It filters what is already loaded; it never invents a server query.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.resultCount,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;

  /// When set and [value] is not empty, announced as "N results".
  final int? resultCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasText = value.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: label,
          value: value,
          placeholder: placeholder,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          trailing: hasText
              ? IconButton(
                  key: const Key('search-clear'),
                  tooltip: 'Clear search',
                  constraints: const BoxConstraints(
                    minWidth: AppSizing.touchTargetMin,
                    minHeight: AppSizing.touchTargetMin,
                  ),
                  icon: Icon(Icons.close, color: t.textSecondary),
                  onPressed: () => onChanged(''),
                )
              : Icon(Icons.search, color: t.textSecondary),
        ),
        if (hasText && resultCount != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                resultCount == 1 ? '1 result' : '$resultCount results',
                key: const Key('search-count'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

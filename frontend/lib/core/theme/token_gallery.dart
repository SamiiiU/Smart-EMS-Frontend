import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'composites_gallery.dart';
import 'primitives_gallery.dart';
import 'scales.dart';
import 'shell_gallery.dart';
import 'states_gallery.dart';
import 'tokens.dart';
import 'typography.dart';

/// A living reference for every token in the design system.
///
/// This is the only screen T1 produces. It exists so the tokens can be SEEN
/// in both light and dark mode, and it stays in the repo permanently — if a
/// token is added, it shows up here, and if it looks wrong here it is wrong.
///
/// It renders from [SmartEmsTokens.colourGroups], [AppSpacing.all],
/// [AppRadius.all], and [AppTypography.all], so it cannot silently drift out
/// of sync with the token definitions.
class TokenGalleryScreen extends StatelessWidget {
  const TokenGalleryScreen({
    required this.isDark,
    required this.onToggleBrightness,
    super.key,
  });

  final bool isDark;
  final VoidCallback onToggleBrightness;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: t.brandSurface,
        foregroundColor: t.onBrand,
        title: Text('Token gallery', style: AppTypography.cardHeading),
        actions: [
          IconButton(
            onPressed: onToggleBrightness,
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: isDark ? 'Switch to light' : 'Switch to dark',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.space6),
        children: [
          _ModeBanner(isDark: isDark),
          const SizedBox(height: AppSpacing.space8),

          // --- Colour tokens -------------------------------------------
          for (final group in t.colourGroups) ...[
            _SectionHeading(group.$1),
            const SizedBox(height: AppSpacing.space4),
            for (final entry in group.$2)
              _Swatch(name: entry.$1, colour: entry.$2),
            const SizedBox(height: AppSpacing.space8),
          ],

          // --- Spacing scale -------------------------------------------
          const _SectionHeading('Spacing scale'),
          const SizedBox(height: AppSpacing.space2),
          const _Note(
            'Fixed set. A value outside it is a defect, not a choice.',
          ),
          const SizedBox(height: AppSpacing.space4),
          for (final step in AppSpacing.all)
            _SpacingRow(name: step.$1, value: step.$2),
          const SizedBox(height: AppSpacing.space8),

          // --- Radius scale --------------------------------------------
          const _SectionHeading('Radius scale'),
          const SizedBox(height: AppSpacing.space4),
          for (final step in AppRadius.all)
            _RadiusRow(name: step.$1, value: step.$2),
          const SizedBox(height: AppSpacing.space8),

          // --- Elevation -----------------------------------------------
          const _SectionHeading('Elevation (D-28)'),
          const SizedBox(height: AppSpacing.space2),
          const _Note(
            'Borders carry structure everywhere — cards, tables, panels, rows. '
            'Shadow is reserved for genuine overlays only: bottom sheets, '
            'dropdowns, dialogs. shadowOverlay is the only shadow token in the '
            'system.',
          ),
          const SizedBox(height: AppSpacing.space5),
          const _ElevationDemo(),
          const SizedBox(height: AppSpacing.space8),

          // --- Typography ----------------------------------------------
          const _SectionHeading('Typography — Plus Jakarta Sans'),
          const SizedBox(height: AppSpacing.space2),
          const _Note(
            'Nothing below 12px. Exactly three weights: 400, 500, 600. '
            'Tabular figures on every style.',
          ),
          const SizedBox(height: AppSpacing.space5),
          for (final style in AppTypography.all)
            _TypeRow(name: style.$1, label: style.$2, style: style.$3),
          const SizedBox(height: AppSpacing.space8),

          // --- Tabular figures proof -----------------------------------
          const _SectionHeading('Tabular figures'),
          const SizedBox(height: AppSpacing.space2),
          const _Note(
            'Digits must occupy equal width so counts, percentages, and PKR '
            'amounts align when stacked. The two columns below should line up '
            'exactly.',
          ),
          const SizedBox(height: AppSpacing.space5),
          const _TabularProof(),
          const SizedBox(height: AppSpacing.space8),

          // --- Per-role base body size ---------------------------------
          const _SectionHeading('Base body size per role (D-24)'),
          const SizedBox(height: AppSpacing.space2),
          const _Note(
            'Set per role shell, not globally. T1 exposes the mechanism; T5 '
            'applies it per shell.',
          ),
          const SizedBox(height: AppSpacing.space5),
          for (final role in AppRole.values) _RoleRow(role: role),
          const SizedBox(height: AppSpacing.space10),

          // --- Primitives (T2) -----------------------------------------
          const PrimitivesGallerySection(),
          const SizedBox(height: AppSpacing.space10),

          // --- Composites (T3) -----------------------------------------
          const CompositesGallerySection(),
          const SizedBox(height: AppSpacing.space10),

          // --- Global states (T4) --------------------------------------
          const StatesGallerySection(),
          const SizedBox(height: AppSpacing.space10),

          // --- Shell and navigation (T5) --------------------------------
          const ShellGallerySection(),
          const SizedBox(height: AppSpacing.space10),
        ],
      ),
    );
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.brandSurface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDark ? 'Dark mode' : 'Light mode',
            style: AppTypography.screenTitle.copyWith(color: t.onBrand),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Toggle with the icon in the app bar. Only colours should change — '
            'no layout shift, no size change, no font change.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.onBrandMuted),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Text(
        text,
        style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
    );
  }
}

/// A labelled colour swatch showing the token name and its resolved hex.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.colour});

  final String name;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hex = '#'
        '${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Row(
        children: [
          Container(
            width: AppSpacing.space10,
            height: AppSpacing.space10,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: t.borderStrong),
            ),
          ),
          const SizedBox(width: AppSpacing.space5),
          Expanded(
            child: Text(
              name,
              style: AppTypography.personName.copyWith(color: t.textPrimary),
            ),
          ),
          Text(
            hex,
            style: AppTypography.timestamp.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SpacingRow extends StatelessWidget {
  const _SpacingRow({required this.name, required this.value});

  final String name;
  final double value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: AppTypography.fieldLabel.copyWith(
                color: t.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(0),
              style: AppTypography.timestamp.copyWith(color: t.textMuted),
            ),
          ),
          Container(
            width: value,
            height: AppSpacing.space6,
            color: t.primaryAction,
          ),
        ],
      ),
    );
  }
}

class _RadiusRow extends StatelessWidget {
  const _RadiusRow({required this.name, required this.value});

  final String name;
  final double value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: AppTypography.fieldLabel.copyWith(
                color: t.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(0),
              style: AppTypography.timestamp.copyWith(color: t.textMuted),
            ),
          ),
          Container(
            width: AppSpacing.space10 * 2,
            height: AppSpacing.space9,
            decoration: BoxDecoration(
              color: t.primarySubtle,
              borderRadius: BorderRadius.circular(value),
              border: Border.all(color: t.primaryAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElevationDemo extends StatelessWidget {
  const _ElevationDemo();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.space5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: t.border),
            ),
            child: Text(
              'Card — border only',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.space5),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: t.shadowOverlay,
            ),
            child: Text(
              'Overlay — shadowOverlay',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.name,
    required this.label,
    required this.style,
  });

  final String name;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name — $label',
            style: AppTypography.overline.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Ayesha Khan · 1,234 · 98% · PKR 45,600',
            style: style.copyWith(color: t.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _TabularProof extends StatelessWidget {
  const _TabularProof();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const rows = [
      ('Class 4-A', '1,111', '11%', 'PKR 11,110'),
      ('Class 9-C', '8,888', '88%', 'PKR 88,880'),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: AppTypography.bodyTeacher.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodyTeacher.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      row.$3,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodyTeacher.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      row.$4,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodyTeacher.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              role.name,
              style: AppTypography.fieldLabel.copyWith(
                color: t.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              role.baseBodySize.toStringAsFixed(0),
              style: AppTypography.timestamp.copyWith(color: t.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              'Attendance marked · 1,234 records',
              style: role.textTheme.bodyMedium?.copyWith(
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

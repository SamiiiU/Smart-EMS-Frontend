import 'package:flutter/material.dart';

import '../widgets/app_button.dart';
import '../widgets/app_data_table.dart';
import '../widgets/avatar.dart';
import '../widgets/context_strip.dart';
import '../widgets/hero_card.dart';
import '../widgets/inline_alert.dart';
import '../widgets/list_row.dart';
import '../widgets/overline.dart';
import '../widgets/section_card.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/tabs.dart';
import 'app_theme.dart';
import 'scales.dart';
import 'typography.dart';

/// The composites half of the living gallery (T3).
///
/// Every variant of all nine composites, so T3 can be reviewed by looking at
/// it. Stateful only because Tabs needs a selected index.
class CompositesGallerySection extends StatefulWidget {
  const CompositesGallerySection({super.key});

  @override
  State<CompositesGallerySection> createState() =>
      _CompositesGallerySectionState();
}

class _CompositesGallerySectionState extends State<CompositesGallerySection> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _H('Composites'),
        const SizedBox(height: AppSpacing.space2),
        const _N(
          'Nine composites, built only from primitives and tokens. No literal '
          'colour, spacing, radius, or size in any of them.',
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- ContextStrip ---------------------------------------------
        const _H('ContextStrip'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Login school strip, diary editing strip, wizard link strip, '
            'CSV file row.'),
        const SizedBox(height: AppSpacing.space5),
        const ContextStrip(
          icon: Icons.school_outlined,
          title: 'Beaconhouse School',
          subtitle: 'Gulberg Campus · Lahore',
        ),
        const SizedBox(height: AppSpacing.space4),
        ContextStrip(
          icon: Icons.edit_outlined,
          title: 'Editing diary',
          subtitle: 'Class 9-C · Mathematics',
          tone: ContextStripTone.neutral,
          trailing: AppButton(
            label: 'Done',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () {},
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        const ContextStrip(
          icon: Icons.insert_drive_file_outlined,
          title: 'students-2026.csv',
          subtitle: '412 rows · 2 warnings',
          tone: ContextStripTone.semantic,
          status: AppStatus.partial,
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- InlineAlert ----------------------------------------------
        const _H('InlineAlert'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Always inline and persistent — never a snackbar. No '
            'duration, no auto-dismiss, no overlay variant.'),
        const SizedBox(height: AppSpacing.space5),
        for (final tone in InlineAlertTone.values) ...[
          InlineAlert(tone: tone, message: _alertMessage(tone)),
          const SizedBox(height: AppSpacing.space4),
        ],
        const SizedBox(height: AppSpacing.space6),

        // --- StatCard -------------------------------------------------
        const _H('StatCard'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Attendance summary strip, admin KPIs, student profile '
            'counters, CSV import counters. Tabular figures throughout.'),
        const SizedBox(height: AppSpacing.space5),
        Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            for (final tone in StatCardTone.values)
              StatCard(
                value: '1,234',
                // Prefixed rather than the bare tone name: the token gallery
                // above renders token names as text, and a bare "success"
                // here would collide with the `success` swatch label.
                label: 'tone: ${tone.name}',
                tone: tone,
                sub: '+12 today',
                onTap: () {},
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- ListRow --------------------------------------------------
        const _H('ListRow'),
        const SizedBox(height: AppSpacing.space2),
        const _N('The whole row is the tap target, not just the trailing '
            'control — asserted in a test.'),
        const SizedBox(height: AppSpacing.space5),
        SectionCard(
          padded: false,
          child: Column(
            children: [
              ListRow(
                leading: const Avatar(initials: 'AK', size: AvatarSize.s40),
                title: 'Ayesha Khan',
                subtitle: 'Roll 12 · Class 9-C',
                trailing: const StatusPill(status: AppStatus.present),
                onTap: () {},
              ),
              ListRow(
                leading: const Avatar(initials: 'BM', size: AvatarSize.s40),
                title: 'Bilal Mehmood',
                subtitle: 'Roll 13 · Class 9-C',
                trailing: const StatusPill(status: AppStatus.absent),
                tint: RowTint.danger,
                onTap: () {},
              ),
              ListRow(
                leading: const Avatar(initials: 'FS', size: AvatarSize.s40),
                title: 'Fatima Siddiqui',
                subtitle: 'Roll 14 · Class 9-C',
                trailing: const StatusPill(status: AppStatus.late),
                tint: RowTint.warning,
                onTap: () {},
              ),
              ListRow(
                title: 'No leading, no subtitle',
                trailing: Icon(Icons.chevron_right, color: t.textMuted),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- PeriodRow ------------------------------------------------
        const _H('PeriodRow'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Fixed 44px time column. Breaks render as a MUTED ROW rather '
            'than being omitted — a gap in a timetable reads as missing data.'),
        const SizedBox(height: AppSpacing.space5),
        SectionCard(
          padded: false,
          child: Column(
            children: [
              PeriodRow(
                time: '08:00',
                title: 'Mathematics',
                subtitle: 'Room 14 · Ms Nadia',
                trailing: const StatusPill(
                  status: AppStatus.complete,
                  size: StatusPillSize.sm,
                ),
                onTap: () {},
              ),
              PeriodRow(
                time: '08:45',
                title: 'Physics',
                subtitle: 'Lab 2 · Mr Adnan',
                onTap: () {},
              ),
              const PeriodRow(
                time: '09:30',
                title: 'Break',
                isBreak: true,
              ),
              PeriodRow(
                time: '09:50',
                title: 'English',
                subtitle: 'Room 9 · Ms Sara',
                trailing: const StatusPill(
                  status: AppStatus.notStarted,
                  size: StatusPillSize.sm,
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- HeroCard -------------------------------------------------
        const _H('HeroCard — brand (NO action, D-23)'),
        const SizedBox(height: AppSpacing.space2),
        const _N('brandSurface. Structurally cannot carry an action: the class '
            'has no action parameter at all.'),
        const SizedBox(height: AppSpacing.space5),
        const HeroCardBrand(
          eyebrow: 'Today',
          title: '96% present',
          subtitle: 'Ayesha was marked present at 08:04',
        ),
        const SizedBox(height: AppSpacing.space6),
        const _H('HeroCard — tinted (carries an action)'),
        const SizedBox(height: AppSpacing.space2),
        const _N('primarySubtle. A primary button on brandSurface would fail '
            'contrast, so an action-carrying hero must be tinted.'),
        const SizedBox(height: AppSpacing.space5),
        HeroCardTinted(
          eyebrow: 'Current period',
          title: 'Mathematics · Class 9-C',
          subtitle: '08:00 – 08:45 · Room 14',
          action: AppButton(
            label: 'Mark attendance',
            fullWidth: true,
            onPressed: () {},
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- SectionCard ----------------------------------------------
        const _H('SectionCard'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Bordered, never shadowed (D-28). Optional header + trailing '
            'action.'),
        const SizedBox(height: AppSpacing.space5),
        SectionCard(
          title: 'Attendance this month',
          trailing: AppButton(
            label: 'View all',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () {},
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Overline('Summary'),
              const SizedBox(height: AppSpacing.space3),
              Text(
                '18 of 20 days present',
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        SectionCard(
          child: Text(
            'No header — body only.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- Tabs -----------------------------------------------------
        const _H('Tabs'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Underline indicator. D-19: a tab with no content is not '
            'rendered — the "Fees" tab below is hidden, not greyed out.'),
        const SizedBox(height: AppSpacing.space5),
        Tabs(
          tabs: const [
            AppTab(label: 'Overview'),
            AppTab(label: 'Attendance'),
            AppTab(label: 'Fees', hasContent: false),
            AppTab(label: 'Remarks'),
          ],
          selectedIndex: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: AppSpacing.space8),

        // --- AppDataTable ---------------------------------------------
        const _H('AppDataTable'),
        const SizedBox(height: AppSpacing.space2),
        const _N('Collapses to stacked cards below 600px and NEVER scrolls '
            'horizontally. Resize the window to see it switch.'),
        const SizedBox(height: AppSpacing.space5),
        SectionCard(
          padded: false,
          child: AppDataTable(
            columns: const ['Student', 'Class', 'Present %'],
            rows: [
              AppDataRow(
                cells: const ['Ayesha Khan', '9-C', '96%'],
                status: AppStatus.active,
                onTap: () {},
              ),
              AppDataRow(
                cells: const ['Bilal Mehmood', '9-C', '71%'],
                status: AppStatus.partial,
                tint: RowTint.warning,
                onTap: () {},
              ),
              AppDataRow(
                cells: const ['Fatima Siddiqui', '10-A', '44%'],
                status: AppStatus.inactive,
                tint: RowTint.danger,
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space10),
      ],
    );
  }

  static String _alertMessage(InlineAlertTone tone) => switch (tone) {
        InlineAlertTone.info =>
          'Re-importing will update existing students, not duplicate them.',
        InlineAlertTone.warning =>
          'Attendance is below 75%. This may affect exam eligibility.',
        InlineAlertTone.danger =>
          'Incorrect mobile number or password. Please try again.',
        InlineAlertTone.success => 'All 412 rows imported successfully.',
      };
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.sectionHeading.copyWith(
          color: context.tokens.textPrimary,
        ),
      );
}

class _N extends StatelessWidget {
  const _N(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.bodyAdminMeta.copyWith(
          color: context.tokens.textSecondary,
        ),
      );
}

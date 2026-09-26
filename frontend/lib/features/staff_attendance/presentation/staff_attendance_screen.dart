import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/staff_attendance_repository.dart';
import '../domain/staff_attendance_models.dart';

/// Screen 6: staff attendance.
///
/// Same ergonomics as the student roll call, because it is the same job:
/// 56px rows, the whole row reachable, one tap per person, the summary
/// visible without scrolling, and no save button — each tap is written
/// immediately, as attendance marking already works.
///
/// What is NOT shared is the vocabulary. Staff have `half_day` and no
/// `excused`; students the reverse. One enum for both would compile and then
/// send an invalid status.
class StaffAttendanceScreen extends StatefulWidget {
  const StaffAttendanceScreen({
    required this.repository,
    this.today,
    super.key,
  });

  final StaffAttendanceRepository repository;

  /// Injectable so a test is not tied to the real clock.
  final DateTime? today;

  @override
  State<StaffAttendanceScreen> createState() => StaffAttendanceScreenState();
}

class StaffAttendanceScreenState extends State<StaffAttendanceScreen> {
  ScreenState<StaffAttendanceDay> _state =
      const ScreenState<StaffAttendanceDay>.loading();

  String? _busyStaffId;
  String? _error;

  late final DateTime _day = widget.today ?? DateTime.now();

  String get _date => '${_day.year}-'
      '${_day.month.toString().padLeft(2, '0')}-'
      '${_day.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _state =
        ScreenState<StaffAttendanceDay>.loading(previous: _state.data));
    try {
      final day = await widget.repository.loadDay(_date);
      if (!mounted) return;
      setState(() => _state = ScreenState<StaffAttendanceDay>.data(
            day,
            // One record for the day, never a collection.
            isEmpty: day.rows.isEmpty,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<StaffAttendanceDay>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<void> _mark(
    StaffAttendanceRow row,
    StaffAttendanceStatus status,
  ) async {
    setState(() {
      _busyStaffId = row.staffId;
      _error = null;
    });
    final error = await widget.repository.mark(
      staffId: row.staffId,
      date: _date,
      status: status,
    );
    if (!mounted) return;
    setState(() {
      _busyStaffId = null;
      _error = error;
    });
    if (error == null) await load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(
        backgroundColor: t.surface,
        surfaceTintColor: t.surface,
        iconTheme: IconThemeData(color: t.textPrimary),
        title: Text(
          'Staff attendance',
          style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space6,
                AppSpacing.space4,
                AppSpacing.space6,
                AppSpacing.none,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _date,
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              ),
            ),
            if (_state.data != null) _Summary(day: _state.data!),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space6,
                  vertical: AppSpacing.space3,
                ),
                child:
                    InlineAlert(tone: InlineAlertTone.danger, message: _error!),
              ),
            Expanded(
              child: ScreenStateBuilder<StaffAttendanceDay>(
                state: _state,
                onRetry: load,
                emptyTitle: 'No staff records',
                emptyMessage: 'There is nobody to mark. Staff are created '
                    'under Add user.',
                emptyIcon: Icons.badge_outlined,
                data: (context, day) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  itemCount: day.rows.length,
                  itemBuilder: (context, i) {
                    final row = day.rows[i];
                    return StaffRow(
                      row: row,
                      enabled: _busyStaffId == null,
                      onMark: (status) => _mark(row, status),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marked / unmarked, from the SERVER's counts rather than the list's, so
/// the header can never disagree with what was saved.
class _Summary extends StatelessWidget {
  const _Summary({required this.day});

  final StaffAttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space6,
        vertical: AppSpacing.space3,
      ),
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${day.totalStaff - day.unmarked} of ${day.totalStaff} marked',
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          Text(
            '${day.present} present',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          Text(
            '${day.absent} absent',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          if (day.unmarked > 0)
            Text(
              '${day.unmarked} left',
              style: AppTypography.bodyAdminMeta
                  .copyWith(color: t.warningTextOnBg),
            ),
        ],
      ),
    );
  }
}

/// One staff member: name, current status, and the five choices.
class StaffRow extends StatelessWidget {
  const StaffRow({
    required this.row,
    required this.enabled,
    required this.onMark,
    super.key,
  });

  final StaffAttendanceRow row;
  final bool enabled;
  final ValueChanged<StaffAttendanceStatus> onMark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space2),
      padding: const EdgeInsets.all(AppSpacing.space4),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                row.fullName,
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              if (row.employeeCode.isNotEmpty)
                Text(
                  row.employeeCode,
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              if (row.status != null)
                StatusPill(status: row.status!.pill, size: StatusPillSize.sm)
              else
                Text(
                  // Not a status — the absence of one. Said in words rather
                  // than shown as a sixth pill that cannot be posted.
                  'Not marked',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.warningTextOnBg),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final status in StaffAttendanceStatus.values)
                _Choice(
                  status: status,
                  selected: row.status == status,
                  enabled: enabled,
                  staffName: row.fullName,
                  onTap: () => onMark(status),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.status,
    required this.selected,
    required this.enabled,
    required this.staffName,
    required this.onTap,
  });

  final StaffAttendanceStatus status;
  final bool selected;
  final bool enabled;
  final String staffName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Mark $staffName ${status.label}',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizing.touchTargetMin,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: selected ? t.primarySubtle : t.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: selected ? t.primaryAccent : t.border,
                width: AppSizing.borderThin,
              ),
            ),
            child: Text(
              status.label,
              style: AppTypography.fieldLabel.copyWith(
                color: selected ? t.primaryTextOnSurface : t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/domain/people_models.dart';
import '../../setup/presentation/academic_years_screen.dart'
    show setupListHeight;
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/complaints_repository.dart';
import '../domain/complaint_models.dart';
import 'complaint_detail_screen.dart';
import 'complaint_row.dart';

/// Screen 3: the admin worklist.
///
/// A worklist, not a report (D-15). Ordered **overdue → unassigned → open →
/// finished**, and oldest first inside each band. An admin opens this to
/// decide what to act on now, and a list ordered by creation date buries the
/// three-week-old one nobody picked up.
///
/// Only the two filters the backend honours as real filters are offered.
/// `assignedTo` exists on the endpoint but needs a staff id the admin would
/// have to know; the assignment state is on every row instead.
class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({
    required this.repository,
    required this.admin,
    super.key,
  });

  final ComplaintsRepository repository;

  /// Only for the staff list a complaint can be assigned to.
  final AdminRepository admin;

  @override
  State<AdminComplaintsScreen> createState() => AdminComplaintsScreenState();
}

class AdminComplaintsScreenState extends State<AdminComplaintsScreen> {
  ScreenState<List<Complaint>> _state =
      const ScreenState<List<Complaint>>.loading();

  List<PersonAccount> _staff = const [];

  ComplaintStatus? _status;
  ComplaintCategory? _category;

  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() =>
        _state = ScreenState<List<Complaint>>.loading(previous: _state.data));
    try {
      final rows = await widget.repository.loadAll(
        status: _status,
        category: _category,
      );
      if (!mounted) return;
      setState(() =>
          _state = ScreenState<List<Complaint>>.data(sortForAdmin(rows, _today)));

      // Best effort: the list is usable without it, and assignment says so
      // if it is missing rather than offering an inert control.
      try {
        final people = await widget.admin.loadPeople();
        if (mounted) setState(() => _staff = people.staff);
      } on Object {
        // Left empty — the detail screen explains it.
      }
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Complaint>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Complaints',
      children: [
        Text(
          'Overdue first, then anything nobody has picked up.',
          style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'Status',
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            PickerChip(
              label: 'All',
              selected: _status == null,
              onTap: () {
                setState(() => _status = null);
                load();
              },
            ),
            for (final s in ComplaintStatus.values)
              PickerChip(
                label: s.label,
                selected: _status == s,
                onTap: () {
                  setState(() => _status = s);
                  load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          'Category',
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            PickerChip(
              label: 'All',
              selected: _category == null,
              onTap: () {
                setState(() => _category = null);
                load();
              },
            ),
            for (final c in ComplaintCategory.values)
              PickerChip(
                label: c.label,
                selected: _category == c,
                onTap: () {
                  setState(() => _category = c);
                  load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Complaint>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nothing to deal with',
            emptyMessage: 'No complaint matches this filter.',
            emptyIcon: Icons.forum_outlined,
            data: (context, rows) => ListView(
              children: [
                for (final complaint in rows)
                  ComplaintRow(
                    complaint: complaint,
                    today: _today,
                    showRaiser: true,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ComplaintDetailScreen(
                            repository: widget.repository,
                            complaintId: complaint.id,
                            staffControls: true,
                            staff: _staff,
                          ),
                        ),
                      );
                      await load();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/admin_repository.dart';
import '../domain/admin_models.dart';

/// The admin's student roster.
///
/// Two backend realities shape this screen:
///
/// - **B-02 — there is no server-side search.** `q`, `search`, `name` and
///   `query` are all silently ignored (verified live: `?q=ZZZNOMATCH` still
///   returns the full set, while an unknown param behaves identically — the
///   control that makes that conclusion sound). So the whole roster is
///   loaded once and filtered in the client, per D-20. **Replace this with
///   a server query when B-02 lands**; it is the only reason
///   [AdminStudent.matches] exists.
/// - **B-03 — the class filter DOES work on this build.** `classId` and
///   `sectionId` both filter correctly (a bogus id returns 0). The earlier
///   instruction to omit the filter rested on the parameter being
///   unconfirmed; it is confirmed, so D-19 does not bar it — there is a
///   backend behind the control.
class StudentsListScreen extends StatefulWidget {
  const StudentsListScreen({
    required this.repository,
    this.onOpenStudent,
    this.onAdmit,
    super.key,
  });

  final AdminRepository repository;
  final void Function(AdminStudent student)? onOpenStudent;

  /// Overhaul M4: opens the guided admission; the list reloads afterwards.
  final Future<void> Function()? onAdmit;

  @override
  State<StudentsListScreen> createState() => StudentsListScreenState();
}

class StudentsListScreenState extends State<StudentsListScreen> {
  ScreenState<List<AdminStudent>> _state =
      const ScreenState<List<AdminStudent>>.loading();

  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state =
        ScreenState<List<AdminStudent>>.loading(previous: _state.data));
    try {
      final students = await widget.repository.loadStudentsWithPlacement();
      if (!mounted) return;
      setState(
          () => _state = ScreenState<List<AdminStudent>>.data(students));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = ScreenState<List<AdminStudent>>.failed(
            e is LoadFailure ? e : const LoadFailure(),
            cached: _state.data,
          ));
    }
  }

  /// Visible rows after the client-side filter (B-02).
  List<AdminStudent> _visible(List<AdminStudent> all) =>
      all.where((s) => s.matches(_query)).toList();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final all = _state.data ?? const <AdminStudent>[];
    final visible = _visible(all);

    // The filter narrowing the list to nothing is a DIFFERENT state from
    // the school having no students (D-14's distinction, applied here):
    // one is cleared by changing the search, the other by importing.
    final filtering = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // M1 shared header: on a narrow phone the action wraps under
                  // the title instead of squeezing it.
                  PageHeader(
                    title: 'Students',
                    padding: EdgeInsets.zero,
                    actions: [
                      if (widget.onAdmit != null)
                        AppButton(
                          key: const Key('open-admit-learner'),
                          label: 'Admit learner',
                          icon: Icons.person_add_alt_1_outlined,
                          onPressed: () async {
                            await widget.onAdmit!();
                            if (mounted) await _load();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  // M1 shared search: clear button + announced result count.
                  SearchField(
                    label: 'Search',
                    value: _query,
                    placeholder: 'Name or admission number',
                    resultCount: visible.length,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ScreenStateBuilder<List<AdminStudent>>(
                state: filtering
                    ? ScreenState<List<AdminStudent>>.data(
                        visible,
                        hasFilter: true,
                      )
                    : _state,
                onRetry: _load,
                emptyTitle: 'No students yet',
                emptyMessage:
                    'Import a roster or create a student to get started.',
                emptyIcon: Icons.groups_outlined,
                filterDescription: filtering ? 'matching “$_query”' : null,
                onClearFilter:
                    filtering ? () => setState(() => _query = '') : null,
                // M1 adaptive list: a table on desktop/tablet, cards on phones.
                data: (context, rows) => AdaptiveDataView<AdminStudent>(
                  rows: rows,
                  semanticLabel: (s) => s.fullName,
                  onTap: widget.onOpenStudent,
                  columns: [
                    DataColumnSpec(label: 'Name', value: (s) => s.fullName, flex: 3),
                    DataColumnSpec(label: 'Admission no.', value: (s) => s.admissionNumber, flex: 2),
                    // Null when the student is enrolled nowhere: a real state,
                    // shown plainly rather than as a blank column.
                    DataColumnSpec(label: 'Class', value: (s) => s.classLabel ?? 'Not enrolled', flex: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

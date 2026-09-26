import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_text_field.dart';
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
    super.key,
  });

  final AdminRepository repository;
  final void Function(AdminStudent student)? onOpenStudent;

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
                  Text(
                    'Students',
                    style: AppTypography.screenTitle
                        .copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  AppTextField(
                    label: 'Search',
                    value: _query,
                    placeholder: 'Name or admission number',
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
                data: (context, rows) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _StudentRow(
                    student: rows[i],
                    onTap: widget.onOpenStudent == null
                        ? null
                        : () => widget.onOpenStudent!(rows[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.onTap});

  final AdminStudent student;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final card = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints:
          const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  student.fullName,
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
                Text(
                  student.admissionNumber,
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
                // Null when the student is enrolled nowhere — a real state,
                // shown plainly rather than as a blank column.
                Text(
                  student.classLabel ?? 'Not enrolled',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: t.textSecondary),
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: student.fullName,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: card),
      ),
    );
  }
}

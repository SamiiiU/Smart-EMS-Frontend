import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../attendance/domain/attendance_models.dart' show RosterStudent;
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

/// Screen 6: teacher remarks about a student.
///
/// ## The visibility control, and why its copy reads the way it does
///
/// The worst failure this screen can produce is a teacher writing a private
/// observation that reaches someone they did not expect. So the consequence
/// is stated **next to the control, at the moment of writing** — not in a
/// tooltip, and not after saving.
///
/// It is also stated ACCURATELY, which matters more than stating it
/// reassuringly. Verified live:
///
///  - a **parent** cannot see a remark flagged `isParentVisible: false`, and
///    cannot reach another child's remarks at all. The flag works for the
///    audience it is named after, which is why this screen ships.
///  - 🔴 a **student** can see it — and can read *other students'* remarks
///    too. The student path has neither a visibility filter nor an ownership
///    check (open item 23, raised as a privacy defect).
///
/// So the copy says "not shown to parents". It does **not** say "private",
/// "staff only" or "only you can see this", because none of those is true
/// today, and a teacher who believed them would write something they should
/// not. No student-facing remarks surface is built until the defect is
/// fixed, and nothing here is filtered client-side.
class RemarksScreen extends StatefulWidget {
  const RemarksScreen({
    required this.repository,
    required this.sectionId,
    required this.sectionName,
    super.key,
  });

  final AcademicsRepository repository;
  final String sectionId;
  final String sectionName;

  @override
  State<RemarksScreen> createState() => RemarksScreenState();
}

class RemarksScreenState extends State<RemarksScreen> {
  ScreenState<List<Remark>> _state = const ScreenState<List<Remark>>.loading();
  List<RosterStudent> _roster = const [];

  String? _studentId;
  String _type = remarkTypes.first;
  String _body = '';
  bool _parentVisible = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(
        () => _state = ScreenState<List<Remark>>.loading(previous: _state.data));
    try {
      final roster = await widget.repository.loadRoster(widget.sectionId);
      final remarks =
          await widget.repository.loadSectionRemarks(widget.sectionId);
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _studentId ??= roster.isEmpty ? null : roster.first.studentId;
        _state = ScreenState<List<Remark>>.data(remarks);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Remark>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<String?> _create() async {
    if (_studentId == null) return 'Choose a student first.';
    try {
      await widget.repository.createRemark(
        studentId: _studentId!,
        sectionId: widget.sectionId,
        remarkType: _type,
        body: _body.trim(),
        isParentVisible: _parentVisible,
      );
      if (!mounted) return null;
      setState(() {
        _body = '';
        _parentVisible = false;
      });
      await load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The remark could not be saved.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Remarks',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message: '${widget.sectionName}. Remarks are the one thing here that '
            'can be corrected or removed after saving.',
      ),
      children: [
        CreatePanel(
          addLabel: 'Write a remark',
          canSubmit: _body.trim().isNotEmpty && _studentId != null,
          onSubmit: _create,
          fields: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final s in _roster)
                        PickerChip(
                          label: s.fullName,
                          selected: _studentId == s.studentId,
                          onTap: () =>
                              setState(() => _studentId = s.studentId),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final type in remarkTypes)
                        PickerChip(
                          label: '${type[0].toUpperCase()}${type.substring(1)}',
                          selected: _type == type,
                          onTap: () => setState(() => _type = type),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: AppTextField(
                label: 'Remark',
                value: _body,
                placeholder: 'What you want recorded about this student',
                onChanged: (v) => setState(() => _body = v),
              ),
            ),
            ParentVisibilityControl(
              parentVisible: _parentVisible,
              onChanged: (v) => setState(() => _parentVisible = v),
            ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Remark>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'No remarks yet',
            emptyMessage: 'Notes written about a student in this section '
                'appear here.',
            emptyIcon: Icons.sticky_note_2_outlined,
            data: (context, remarks) => ListView(
              children: [
                for (final remark in remarks) _RemarkRow(remark: remark),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The parent-visible control, with the consequence beside it.
///
/// Deliberately not a bare switch labelled "Parent visible": the two states
/// are spelled out, because the teacher is deciding who reads this and the
/// answer has to be readable without thinking about which way a toggle
/// points.
class ParentVisibilityControl extends StatelessWidget {
  const ParentVisibilityControl({
    required this.parentVisible,
    required this.onChanged,
    super.key,
  });

  final bool parentVisible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: parentVisible ? t.infoBg : t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: parentVisible ? t.info : t.border,
          width: AppSizing.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Show this to the parent',
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
              ),
              Semantics(
                label: 'Show this remark to the parent',
                toggled: parentVisible,
                child: Switch.adaptive(
                  value: parentVisible,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          // The consequence, in full, at the moment of writing.
          Text(
            parentVisible
                ? 'The parent will see this remark in their app.'
                : 'The parent will not see this remark.',
            style: AppTypography.bodyAdminMeta.copyWith(
              color: parentVisible ? t.infoTextOnBg : t.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),
          // And the honest limit of that promise.
          Text(
            'Other staff can always see it, and so can the student. Only the '
            'parent’s view is controlled here.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RemarkRow extends StatelessWidget {
  const _RemarkRow({required this.remark});

  final Remark remark;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
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
            runSpacing: AppSpacing.space1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                remark.studentName,
                style: AppTypography.personName.copyWith(color: t.textPrimary),
              ),
              Text(
                remark.remarkType,
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
              // Stated in words on every row, so scanning a list never
              // requires remembering what a colour meant.
              Text(
                remark.isParentVisible ? 'Parent can see' : 'Not shown to parent',
                style: AppTypography.bodyAdminMeta.copyWith(
                  color: remark.isParentVisible
                      ? t.infoTextOnBg
                      : t.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            remark.body,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            '${remark.authorName} · ${remark.remarkDate}',
            style: AppTypography.timestamp.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

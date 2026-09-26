import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/domain/people_models.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';
import 'academic_years_screen.dart' show setupListHeight;
import 'sections_screen.dart' show PickerChip;
import 'setup_scaffold.dart';

/// Step 5: who teaches what, per section.
///
/// **Built around a section, not a list of assignments**, because that is
/// how an admin thinks: "who teaches what in 9-C", never "show me every
/// assignment".
///
/// 🔴 **Add-only, and the screen says so before the action.** This backend
/// has no update or delete for an assignment (PUT/DELETE → 404, verified),
/// so a wrong teacher is permanent. There is no edit control and no
/// disabled one either — a picker that implied editability would be the
/// D-19 failure. The warning is shown on the form, above the save, so an
/// admin chooses carefully rather than finding out afterwards.
class TeachingAssignmentsScreen extends StatefulWidget {
  const TeachingAssignmentsScreen({
    required this.repository,
    required this.admin,
    required this.classes,
    required this.sections,
    required this.subjects,
    required this.year,
    super.key,
  });

  final SetupRepository repository;
  final AdminRepository admin;
  final List<SchoolClass> classes;
  final List<Section> sections;
  final List<Subject> subjects;
  final AcademicYear year;

  @override
  State<TeachingAssignmentsScreen> createState() =>
      TeachingAssignmentsScreenState();
}

class TeachingAssignmentsScreenState
    extends State<TeachingAssignmentsScreen> {
  ScreenState<List<TeachingAssignment>> _state =
      const ScreenState<List<TeachingAssignment>>.loading();

  List<PersonAccount> _staff = const [];
  late Section _section = _sectionsThisYear.first;
  String? _subjectId;
  String? _staffId;

  List<Section> get _sectionsThisYear {
    final mine = widget.sections
        .where((s) => s.academicYearId == widget.year.id)
        .toList();
    return mine.isEmpty ? widget.sections : mine;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = ScreenState<List<TeachingAssignment>>.loading(
          previous: _state.data,
        ));
    try {
      final rows = await widget.repository.loadAssignments(_section.id);
      List<PersonAccount> staff = _staff;
      if (staff.isEmpty) {
        try {
          staff = (await widget.admin.loadPeople()).staff;
        } on Object {
          staff = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _state = ScreenState<List<TeachingAssignment>>.data(rows);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<TeachingAssignment>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  String _classNameFor(Section s) => widget.classes
      .firstWhere(
        (c) => c.id == s.classId,
        orElse: () => const SchoolClass(id: '', name: 'Class'),
      )
      .name;

  String _subjectName(String id) => widget.subjects
      .firstWhere(
        (s) => s.id == id,
        orElse: () => const Subject(id: '', name: 'Unknown subject'),
      )
      .name;

  String _staffName(String id) => _staff
      .firstWhere(
        (s) => s.id == id,
        orElse: () => const PersonAccount(
          id: '',
          fullName: 'Unknown teacher',
          group: PeopleGroup.staff,
        ),
      )
      .fullName;

  Future<String?> _create() async {
    final subjectId = _subjectId;
    final staffId = _staffId;
    if (subjectId == null || staffId == null) return 'Pick a subject and a teacher.';
    try {
      await widget.repository.createAssignment(
        staffId: staffId,
        sectionId: _section.id,
        subjectId: subjectId,
        academicYearId: widget.year.id,
      );
      if (!mounted) return null;
      setState(() {
        _subjectId = null;
        _staffId = null;
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      // The one expected failure: this subject already has a teacher in this
      // section for this year. Said in those words rather than "conflict".
      final message = f.message ?? '';
      if (message.contains('Conflicts with existing data')) {
        return '${_subjectName(subjectId)} already has a teacher in '
            '${_section.name} for ${widget.year.name}. It cannot be '
            'changed yet.';
      }
      return message.isEmpty ? 'The assignment could not be saved.' : message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sections = _sectionsThisYear;

    return SetupScaffold(
      title: 'Who teaches what',
      note: const InlineAlert(
        tone: InlineAlertTone.warning,
        message: 'An assignment cannot be changed or removed yet, so check '
            'the teacher before saving.',
      ),
      children: [
        Text(
          'Section',
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space3),
        Wrap(
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            for (final s in sections)
              PickerChip(
                label: '${_classNameFor(s)} · ${s.name}',
                selected: s.id == _section.id,
                onTap: () {
                  setState(() => _section = s);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        CreatePanel(
          addLabel: 'Assign a teacher',
          canSubmit: _subjectId != null && _staffId != null,
          confirmNote: 'This cannot be changed or removed afterwards.',
          onSubmit: _create,
          fields: [
            Text(
              'Subject',
              style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space3),
            Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space3,
              children: [
                for (final s in widget.subjects)
                  PickerChip(
                    label: s.name,
                    selected: s.id == _subjectId,
                    onTap: () => setState(() => _subjectId = s.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space5),
            Text(
              'Teacher',
              style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space3),
            if (_staff.isEmpty)
              Text(
                'No staff could be loaded, so no teacher can be picked yet.',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              )
            else
              Wrap(
                spacing: AppSpacing.space3,
                runSpacing: AppSpacing.space3,
                children: [
                  for (final s in _staff)
                    PickerChip(
                      label: s.fullName,
                      selected: s.id == _staffId,
                      onTap: () => setState(() => _staffId = s.id),
                    ),
                ],
              ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<TeachingAssignment>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'Nobody assigned yet',
            emptyMessage:
                'Assign a teacher to each subject this section studies. The '
                'timetable needs these.',
            emptyIcon: Icons.assignment_ind_outlined,
            data: (context, rows) => ListView(
              children: [
                for (final a in rows)
                  SetupRow(
                    title: _subjectName(a.subjectId),
                    detail: _staffName(a.staffId),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
import 'setup_scaffold.dart';

/// Step 3: sections, grouped by class.
///
/// **The academic year is stated, never implied.** A section belongs to a
/// class AND a year; if the year were invisible, an admin looking at a new
/// year would think last year's sections had vanished.
///
/// Grouping happens in the client because `?classId=` is ignored by this
/// backend (verified with a bogus-id control), so the whole list is loaded
/// and split here.
class SectionsScreen extends StatefulWidget {
  const SectionsScreen({
    required this.repository,
    required this.admin,
    required this.classes,
    required this.year,
    super.key,
  });

  final SetupRepository repository;
  final AdminRepository admin;
  final List<SchoolClass> classes;
  final AcademicYear year;

  @override
  State<SectionsScreen> createState() => SectionsScreenState();
}

class SectionsScreenState extends State<SectionsScreen> {
  ScreenState<List<Section>> _state =
      const ScreenState<List<Section>>.loading();

  List<PersonAccount> _staff = const [];

  late String _classId = widget.classes.first.id;
  String _name = '';
  String _capacity = '';
  String? _classTeacherId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
        () => _state = ScreenState<List<Section>>.loading(previous: _state.data));
    try {
      final sections = await widget.repository.loadSections();
      // The class-teacher picker needs staff; a failure there must not stop
      // sections from loading, so it is fetched separately and tolerated.
      List<PersonAccount> staff = const [];
      try {
        staff = (await widget.admin.loadPeople()).staff;
      } on Object {
        staff = const [];
      }
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _state = ScreenState<List<Section>>.data(sections);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Section>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  bool get _capacityValid =>
      _capacity.trim().isEmpty || int.tryParse(_capacity.trim()) != null;

  Future<String?> _create() async {
    try {
      await widget.repository.createSection(
        classId: _classId,
        academicYearId: widget.year.id,
        name: _name.trim(),
        capacity: int.tryParse(_capacity.trim()),
        classTeacherId: _classTeacherId,
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _capacity = '';
        _classTeacherId = null;
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The section could not be created.';
    }
  }

  String _classNameFor(String id) => widget.classes
      .firstWhere(
        (c) => c.id == id,
        orElse: () => const SchoolClass(id: '', name: 'Another class'),
      )
      .name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final teachers = _staff.where((s) => s.hasLogin || true).toList();

    return SetupScaffold(
      title: 'Sections',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message: 'Sections created here belong to ${widget.year.name}'
            '${widget.year.current ? ' (the current year)' : ''}. A new '
            'year needs its own sections.',
      ),
      children: [
        CreatePanel(
          addLabel: 'Add a section',
          canSubmit: _name.trim().isNotEmpty && _capacityValid,
          onSubmit: _create,
          fields: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: _Picker<SchoolClass>(
                label: 'Class',
                items: widget.classes,
                selectedId: _classId,
                idOf: (c) => c.id,
                labelOf: (c) => c.name,
                onSelect: (c) {
                  if (c != null) setState(() => _classId = c.id);
                },
              ),
            ),
            SetupField(
              label: 'Section name',
              value: _name,
              placeholder: 'e.g. A',
              onChanged: (v) => setState(() => _name = v),
            ),
            SetupField(
              label: 'Capacity (optional)',
              value: _capacity,
              placeholder: 'e.g. 35',
              onChanged: (v) => setState(() => _capacity = v),
            ),
            if (!_capacityValid)
              Text(
                'Capacity must be a whole number.',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
            if (teachers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.space4),
                child: _Picker<PersonAccount>(
                  label: 'Class teacher (optional)',
                  items: teachers,
                  selectedId: _classTeacherId,
                  idOf: (s) => s.id,
                  labelOf: (s) => s.fullName,
                  allowNone: true,
                  onSelect: (s) => setState(() => _classTeacherId = s?.id),
                ),
              ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Section>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No sections yet',
            emptyMessage:
                'Students are enrolled into a section, so every class needs '
                'at least one.',
            emptyIcon: Icons.grid_view_outlined,
            data: (context, all) {
              final mine =
                  all.where((s) => s.academicYearId == widget.year.id).toList();
              if (mine.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space6),
                    child: Text(
                      all.isEmpty
                          ? 'No sections yet.'
                          : 'No sections in ${widget.year.name} yet. '
                              '${all.length} exist in other years.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyAdminMeta
                          .copyWith(color: t.textSecondary),
                    ),
                  ),
                );
              }
              final byClass = <String, List<Section>>{};
              for (final s in mine) {
                byClass.putIfAbsent(s.classId, () => []).add(s);
              }
              return ListView(
                children: [
                  for (final c in widget.classes)
                    if (byClass[c.id] != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.space3,
                          bottom: AppSpacing.space3,
                        ),
                        child: Text(
                          c.name,
                          style: AppTypography.overline
                              .copyWith(color: t.textSecondary),
                        ),
                      ),
                      for (final s in byClass[c.id]!)
                        SetupRow(
                          title: s.name,
                          detail: s.capacity == null
                              ? 'No capacity set'
                              : 'Capacity ${s.capacity}',
                          trailing: s.classTeacherId == null
                              ? 'No class teacher'
                              : null,
                        ),
                    ],
                  // Sections whose class is not in the list — the backend
                  // allows a class to be deleted while its sections live on,
                  // so this is a real state, not a defensive branch.
                  for (final entry in byClass.entries)
                    if (!widget.classes.any((c) => c.id == entry.key)) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.space3,
                        ),
                        child: Text(
                          '${_classNameFor(entry.key)} (class no longer exists)',
                          style: AppTypography.overline
                              .copyWith(color: t.warningTextOnBg),
                        ),
                      ),
                      for (final s in entry.value)
                        SetupRow(title: s.name, detail: 'Orphaned section'),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A chip picker. Used instead of a dropdown so the options are visible
/// without a second tap, which matters when there are three classes and the
/// admin is learning the order things must happen in.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.items,
    required this.selectedId,
    required this.idOf,
    required this.labelOf,
    required this.onSelect,
    this.allowNone = false,
  });

  final String label;
  final List<T> items;
  final String? selectedId;
  final String Function(T) idOf;
  final String Function(T) labelOf;
  final void Function(T?) onSelect;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space3),
        Wrap(
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            if (allowNone)
              PickerChip(
                label: 'None',
                selected: selectedId == null,
                onTap: () => onSelect(null),
              ),
            for (final item in items)
              PickerChip(
                label: labelOf(item),
                selected: idOf(item) == selectedId,
                onTap: () => onSelect(item),
              ),
          ],
        ),
      ],
    );
  }
}

/// One option in a picker — the same chip the wizard and Accounts use.
class PickerChip extends StatelessWidget {
  const PickerChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space3,
            ),
            decoration: BoxDecoration(
              color: selected ? t.primarySubtle : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: selected ? t.primaryAccent : t.border,
              ),
            ),
            child: Text(
              label,
              style: AppTypography.fieldLabel.copyWith(
                color: selected ? t.textPrimary : t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

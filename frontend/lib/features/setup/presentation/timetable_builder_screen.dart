import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/domain/people_models.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';
import 'sections_screen.dart' show PickerChip;
import 'setup_scaffold.dart';

/// Step 6: the timetable.
///
/// Two halves, because the backend has two: **periods are school-wide**
/// (and carry `isBreak`), **slots are per section**.
///
/// **Layout.** Above [AppSizing.tableCollapseBreakpoint] the week is a grid,
/// days down and periods across. Below it there is no grid at all — a day
/// picker and that day's periods as rows. A six-by-eight grid at 360px is
/// unreadable at any text scale, and a horizontally scrolling table hides
/// half the week behind a gesture nobody discovers.
///
/// **Failures land on the cell.** One POST per cell, so a failure belongs to
/// exactly one cell and is shown there — an admin filling forty slots cannot
/// act on "save failed".
///
/// 🔴 **A 409 does not mean a clash on this backend.** Validation failures
/// answer 409 too, so the message decides (see [SlotFailure]): the known
/// clash wordings render as a clash, and anything else is shown verbatim
/// rather than dressed up as a conflict that may not exist.
class TimetableBuilderScreen extends StatefulWidget {
  const TimetableBuilderScreen({
    required this.repository,
    required this.admin,
    required this.campusId,
    required this.classes,
    required this.sections,
    required this.subjects,
    required this.year,
    super.key,
  });

  final SetupRepository repository;
  final AdminRepository admin;
  final String campusId;
  final List<SchoolClass> classes;
  final List<Section> sections;
  final List<Subject> subjects;
  final AcademicYear year;

  @override
  State<TimetableBuilderScreen> createState() => TimetableBuilderScreenState();
}

class TimetableBuilderScreenState extends State<TimetableBuilderScreen> {
  static const List<(int, String)> days = [
    (1, 'Mon'),
    (2, 'Tue'),
    (3, 'Wed'),
    (4, 'Thu'),
    (5, 'Fri'),
    (6, 'Sat'),
  ];

  ScreenState<_Week> _state = const ScreenState<_Week>.loading();

  List<PersonAccount> _staff = const [];
  late Section _section = _sectionsThisYear.first;
  int _day = DateTime.now().weekday.clamp(1, 6);

  /// Cell key (`day-periodId`) → the failure to show on it.
  final Map<String, SlotFailure> _cellErrors = {};

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
    setState(() => _state = ScreenState<_Week>.loading(previous: _state.data));
    try {
      final periods = await widget.repository.loadPeriods(widget.campusId);
      final slots = await widget.repository.loadWeek(
        sectionId: _section.id,
        academicYearId: widget.year.id,
      );
      List<Room> rooms = const [];
      try {
        rooms = await widget.repository.loadRooms(widget.campusId);
      } on Object {
        rooms = const [];
      }
      if (_staff.isEmpty) {
        try {
          _staff = (await widget.admin.loadPeople()).staff;
        } on Object {
          _staff = const [];
        }
      }
      if (!mounted) return;
      setState(() => _state = ScreenState<_Week>.data(
            _Week(periods: periods, slots: slots, rooms: rooms),
            isEmpty: periods.isEmpty,
          ));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<_Week>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  String _cellKey(int day, String periodId) => '$day-$periodId';

  String _subjectName(String id) => widget.subjects
      .firstWhere(
        (s) => s.id == id,
        orElse: () => const Subject(id: '', name: 'Subject'),
      )
      .name;

  String _staffName(String id) => _staff
      .firstWhere(
        (s) => s.id == id,
        orElse: () => const PersonAccount(
          id: '',
          fullName: 'Teacher',
          group: PeopleGroup.staff,
        ),
      )
      .fullName;

  Future<void> _fill(SchoolPeriod period, int day, _Week week) async {
    final choice = await showModalBottomSheet<_SlotChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      builder: (_) => _SlotSheet(
        title: '${_dayLabel(day)} · ${period.name}',
        subjects: widget.subjects,
        staff: _staff,
        rooms: week.rooms,
      ),
    );
    if (choice == null || !mounted) return;

    final (slot, failure) = await widget.repository.createSlot(
      sectionId: _section.id,
      academicYearId: widget.year.id,
      periodId: period.id,
      dayOfWeek: day,
      subjectId: choice.subjectId,
      teacherStaffId: choice.staffId,
      roomId: choice.roomId,
    );
    if (!mounted) return;

    setState(() {
      final key = _cellKey(day, period.id);
      if (failure != null) {
        _cellErrors[key] = failure;
      } else {
        _cellErrors.remove(key);
        if (slot != null) {
          _state = ScreenState<_Week>.data(
            week.withSlot(slot),
            isEmpty: false,
          );
        }
      }
    });
  }

  static String _dayLabel(int day) =>
      days.firstWhere((d) => d.$1 == day, orElse: () => (day, '?')).$2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sections = _sectionsThisYear;

    return SetupScaffold(
      title: 'Timetable',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message: 'Periods are the same for the whole school. This week '
            'belongs to ${widget.year.name}.',
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
                label: s.name,
                selected: s.id == _section.id,
                onTap: () {
                  setState(() {
                    _section = s;
                    _cellErrors.clear();
                  });
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        _PeriodCreator(
          repository: widget.repository,
          campusId: widget.campusId,
          onCreated: _load,
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ScreenStateBuilder<_Week>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No periods yet',
            emptyMessage:
                'Add the school day’s periods first — they are shared by '
                'every section.',
            emptyIcon: Icons.schedule_outlined,
            data: (context, week) => LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= AppSizing.tableCollapseBreakpoint
                      ? _grid(context, week)
                      : _dayList(context, week),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, _Week week, SchoolPeriod p, int day) {
    final t = context.tokens;
    final slot = week.slotFor(day, p.id);
    final error = _cellErrors[_cellKey(day, p.id)];

    final body = Container(
      margin: const EdgeInsets.all(AppSpacing.space1),
      padding: const EdgeInsets.all(AppSpacing.space3),
      constraints:
          const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: error != null
            ? t.dangerBg
            : slot != null
                ? t.primarySubtle
                : t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            slot == null ? '—' : _subjectName(slot.subjectId),
            style: AppTypography.bodyAdminMeta.copyWith(
              color: error != null ? t.dangerTextOnBg : t.textPrimary,
            ),
          ),
          if (slot != null)
            Text(
              _staffName(slot.teacherStaffId),
              style: AppTypography.overline.copyWith(color: t.textSecondary),
            ),
          if (error != null)
            Text(
              _cellMessage(error),
              style:
                  AppTypography.overline.copyWith(color: t.dangerTextOnBg),
            ),
        ],
      ),
    );

    if (slot != null) return body;
    return Semantics(
      button: true,
      label: '${_dayLabel(day)} ${p.name}, empty',
      child: GestureDetector(
        onTap: () => _fill(p, day, week),
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(child: body),
      ),
    );
  }

  /// What the admin is told on a failed cell.
  ///
  /// A clash names the person or the room and admits what the app cannot
  /// tell them — the API does not say WHICH class the clash is with, and
  /// silently omitting that would send them looking through every section.
  String _cellMessage(SlotFailure failure) => switch (failure.kind) {
        SlotFailureKind.teacherClash =>
          'This teacher already teaches at this time, elsewhere. The app '
              'cannot yet show which class.',
        SlotFailureKind.roomClash =>
          'This room is already booked at this time, elsewhere. The app '
              'cannot yet show which class.',
        SlotFailureKind.other => failure.message,
      };

  Widget _grid(BuildContext context, _Week week) {
    final t = context.tokens;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: AppSizing.statCardSkeletonWidth,
                child: Text(
                  'Day',
                  style:
                      AppTypography.overline.copyWith(color: t.textSecondary),
                ),
              ),
              for (final p in week.teaching)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: AppTypography.overline
                              .copyWith(color: t.textSecondary),
                        ),
                        Text(
                          p.timeLabel,
                          style: AppTypography.overline
                              .copyWith(color: t.textDisabled),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          for (final (day, label) in days) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSizing.statCardSkeletonWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.space3),
                    child: Text(
                      label,
                      style: AppTypography.personName
                          .copyWith(color: t.textPrimary),
                    ),
                  ),
                ),
                for (final p in week.teaching)
                  Expanded(child: _cell(context, week, p, day)),
              ],
            ),
          ],
          if (week.breaks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space5),
            for (final b in week.breaks) _BreakBand(period: b),
          ],
        ],
      ),
    );
  }

  Widget _dayList(BuildContext context, _Week week) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            for (final (day, label) in days)
              PickerChip(
                label: label,
                selected: day == _day,
                onTap: () => setState(() => _day = day),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        Expanded(
          child: ListView(
            children: [
              for (final p in week.periods)
                if (p.isBreak)
                  _BreakBand(period: p)
                else
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.space2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: AppSizing.statCardSkeletonWidth,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(top: AppSpacing.space3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: AppTypography.bodyAdminMeta
                                      .copyWith(color: t.textPrimary),
                                ),
                                Text(
                                  p.timeLabel,
                                  style: AppTypography.overline
                                      .copyWith(color: t.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: _cell(context, week, p, _day)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A break, drawn as a full-width band rather than a cell: it is school-wide
/// and never holds a slot, so a per-day cell would invite a tap that cannot
/// succeed.
class _BreakBand extends StatelessWidget {
  const _BreakBand({required this.period});

  final SchoolPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space5,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        '${period.name} · ${period.timeLabel}',
        style: AppTypography.overline.copyWith(color: t.textSecondary),
      ),
    );
  }
}

/// Adds a school-wide period. Create-only: this backend has no PUT or
/// DELETE for periods, so the form says so before it is used.
class _PeriodCreator extends StatefulWidget {
  const _PeriodCreator({
    required this.repository,
    required this.campusId,
    required this.onCreated,
  });

  final SetupRepository repository;
  final String campusId;
  final Future<void> Function() onCreated;

  @override
  State<_PeriodCreator> createState() => _PeriodCreatorState();
}

class _PeriodCreatorState extends State<_PeriodCreator> {
  String _name = '';
  String _start = '';
  String _end = '';
  String _order = '';
  bool _isBreak = false;

  bool get _valid =>
      _name.trim().isNotEmpty &&
      _isTime(_start) &&
      _isTime(_end) &&
      int.tryParse(_order.trim()) != null;

  static bool _isTime(String v) =>
      RegExp(r'^\d{2}:\d{2}$').hasMatch(v.trim());

  Future<String?> _create() async {
    try {
      await widget.repository.createPeriod(
        campusId: widget.campusId,
        name: _name.trim(),
        startTime: '${_start.trim()}:00',
        endTime: '${_end.trim()}:00',
        sortOrder: int.parse(_order.trim()),
        isBreak: _isBreak,
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _start = '';
        _end = '';
        _order = '';
        _isBreak = false;
      });
      await widget.onCreated();
      return null;
    } on LoadFailure catch (f) {
      // This endpoint answers 409 for bad input as well as for a real
      // conflict, so the backend's own words are shown rather than a guess.
      return f.message ?? 'The period could not be created.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return CreatePanel(
      addLabel: 'Add a period',
      canSubmit: _valid,
      confirmNote: 'Periods apply to the whole school and cannot be edited '
          'or removed afterwards.',
      onSubmit: _create,
      fields: [
        SetupField(
          label: 'Name',
          value: _name,
          placeholder: 'e.g. Period 1, or Break',
          onChanged: (v) => setState(() => _name = v),
        ),
        SetupField(
          label: 'Starts',
          value: _start,
          placeholder: 'HH:MM',
          onChanged: (v) => setState(() => _start = v),
        ),
        SetupField(
          label: 'Ends',
          value: _end,
          placeholder: 'HH:MM',
          onChanged: (v) => setState(() => _end = v),
        ),
        SetupField(
          label: 'Order in the day',
          value: _order,
          placeholder: 'e.g. 1',
          onChanged: (v) => setState(() => _order = v),
        ),
        Row(
          children: [
            Checkbox(
              value: _isBreak,
              onChanged: (v) => setState(() => _isBreak = v ?? false),
            ),
            Expanded(
              child: Text(
                'This is a break (no classes are taught)',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the sheet returns.
@immutable
class _SlotChoice {
  const _SlotChoice({
    required this.subjectId,
    required this.staffId,
    this.roomId,
  });

  final String subjectId;
  final String staffId;
  final String? roomId;
}

class _SlotSheet extends StatefulWidget {
  const _SlotSheet({
    required this.title,
    required this.subjects,
    required this.staff,
    required this.rooms,
  });

  final String title;
  final List<Subject> subjects;
  final List<PersonAccount> staff;
  final List<Room> rooms;

  @override
  State<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends State<_SlotSheet> {
  String? _subjectId;
  String? _staffId;
  String? _roomId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: AppTypography.cardHeading.copyWith(color: t.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space5),
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
            Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space3,
              children: [
                for (final s in widget.staff)
                  PickerChip(
                    label: s.fullName,
                    selected: s.id == _staffId,
                    onTap: () => setState(() => _staffId = s.id),
                  ),
              ],
            ),
            if (widget.rooms.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.space5),
              Text(
                'Room (optional)',
                style:
                    AppTypography.fieldLabel.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: AppSpacing.space3),
              Wrap(
                spacing: AppSpacing.space3,
                runSpacing: AppSpacing.space3,
                children: [
                  PickerChip(
                    label: 'None',
                    selected: _roomId == null,
                    onTap: () => setState(() => _roomId = null),
                  ),
                  for (final r in widget.rooms)
                    PickerChip(
                      label: r.name,
                      selected: r.id == _roomId,
                      onTap: () => setState(() => _roomId = r.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.space6),
            AppButton(
              label: 'Add to timetable',
              fullWidth: true,
              onPressed: _subjectId == null || _staffId == null
                  ? null
                  : () => Navigator.of(context).pop(
                        _SlotChoice(
                          subjectId: _subjectId!,
                          staffId: _staffId!,
                          roomId: _roomId,
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Periods + the section's slots + rooms, as one loaded value.
@immutable
class _Week {
  const _Week({
    required this.periods,
    required this.slots,
    required this.rooms,
  });

  final List<SchoolPeriod> periods;
  final List<TimetableSlot> slots;
  final List<Room> rooms;

  List<SchoolPeriod> get teaching =>
      periods.where((p) => !p.isBreak).toList();
  List<SchoolPeriod> get breaks => periods.where((p) => p.isBreak).toList();

  TimetableSlot? slotFor(int day, String periodId) {
    for (final s in slots) {
      if (s.dayOfWeek == day && s.periodId == periodId) return s;
    }
    return null;
  }

  _Week withSlot(TimetableSlot slot) =>
      _Week(periods: periods, slots: [...slots, slot], rooms: rooms);
}

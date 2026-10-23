import 'package:flutter/material.dart';

import '../../../core/shell/campus_context.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/data/setup_repository.dart';
import '../../setup/domain/setup_models.dart';
import '../data/admission_repository.dart';

/// Overhaul M4: guided learner admission (no login needed).
///
/// Learner → Placement → Guardian (optional) → Review. Nothing is written until
/// the admin confirms on Review; a failure after the learner was created is
/// resumed from the failed step, never by creating the learner again.
class AdmitLearnerScreen extends StatefulWidget {
  const AdmitLearnerScreen({
    required this.admissions,
    required this.setup,
    this.campuses,
    this.onAdmitted,
    super.key,
  });

  final AdmissionRepository admissions;
  final SetupRepository setup;

  /// Campuses this account may admit into; defaults to the campus context.
  final List<CampusOption>? campuses;
  final ValueChanged<String>? onAdmitted;

  @override
  State<AdmitLearnerScreen> createState() => _AdmitLearnerScreenState();
}

class _AdmitLearnerScreenState extends State<AdmitLearnerScreen> {
  static const _titles = ['Learner', 'Placement', 'Guardian', 'Review'];
  final _draft = AdmissionDraft();
  final _progress = AdmissionProgress();
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _admittedId;

  List<AcademicYear> _years = const [];
  List<Section> _sections = const [];
  Map<String, String> _classNames = const {};
  bool _setupLoaded = false;
  String? _setupError;

  List<CampusOption> get _campuses =>
      widget.campuses ?? CampusScope.maybeOf(context)?.options ?? const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draft.campusId == null && _campuses.length == 1)
      _draft.campusId = _campuses.single.id;
    if (!_setupLoaded) _loadSetup();
  }

  Future<void> _loadSetup() async {
    _setupLoaded = true;
    try {
      final years = await widget.setup.loadYears();
      final sections = await widget.setup.loadSections();
      final classes = await widget.setup.loadClasses();
      if (!mounted) return;
      setState(() {
        _years = years;
        _sections = sections;
        _classNames = {for (final c in classes) c.id: c.name};
        _preselectYear();
      });
    } on LoadFailure catch (f) {
      if (mounted)
        setState(
          () => _setupError =
              f.message ?? 'Years and sections could not be loaded.',
        );
    }
  }

  List<AcademicYear> get _campusYears => _years
      .where((y) => y.campusId == null || y.campusId == _draft.campusId)
      .toList();
  List<Section> get _yearSections =>
      _sections.where((s) => s.academicYearId == _draft.academicYearId).toList()
        ..sort((a, b) => _sectionLabel(a).compareTo(_sectionLabel(b)));
  String _sectionLabel(Section s) =>
      '${_classNames[s.classId] ?? 'Class'} · ${s.name}';

  void _preselectYear() {
    final years = _campusYears;
    if (years.isEmpty) return;
    _draft.academicYearId ??=
        (years.where((y) => y.current).firstOrNull ?? years.first).id;
  }

  bool get _canAdvance => switch (_step) {
    0 => _draft.learnerReady,
    1 => _draft.placementReady,
    2 => _draft.guardianReady,
    _ => true,
  };

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.admissions.submit(_draft, _progress);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (outcome) {
        case AdmissionDone(:final studentId):
          _admittedId = studentId;
          widget.onAdmitted?.call(studentId);
        case AdmissionFailed(:final step, :final failure):
          final saved = _progress.started
              ? ' The learner record is saved; retrying continues from here.'
              : '';
          _error =
              '${failure.message ?? 'The $step step could not be saved.'}$saved';
          if (step == 'learner') _step = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      appBar: AppBar(title: const Text('Admit learner')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.space6),
              children: _admittedId != null ? _done(t) : _form(t),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _done(SmartEmsTokens t) => [
    Semantics(
      liveRegion: true,
      child: InlineAlert(
        tone: InlineAlertTone.success,
        message:
            '${_draft.firstName.trim()} ${_draft.lastName.trim()} is admitted'
            '${_progress.enrolled ? ' and placed in ${_sectionLabelFor(_draft.sectionId)}' : ''}.',
      ),
    ),
    const SizedBox(height: AppSpacing.space6),
    AppButton(
      key: const Key('admit-another'),
      label: 'Admit another learner',
      fullWidth: true,
      onPressed: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AdmitLearnerScreen(
            admissions: widget.admissions,
            setup: widget.setup,
            campuses: widget.campuses,
            onAdmitted: widget.onAdmitted,
          ),
        ),
      ),
    ),
  ];

  String _sectionLabelFor(String? id) {
    final s = _sections.where((x) => x.id == id).firstOrNull;
    return s == null ? 'the chosen section' : _sectionLabel(s);
  }

  List<Widget> _form(SmartEmsTokens t) => [
    Semantics(
      header: true,
      child: Text(
        'Step ${_step + 1} of ${_titles.length} · ${_titles[_step]}',
        style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
      ),
    ),
    const SizedBox(height: AppSpacing.space3),
    ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: LinearProgressIndicator(
        value: (_step + 1) / _titles.length,
        minHeight: 6,
        color: t.primaryAccent,
        backgroundColor: t.border,
        semanticsLabel: 'Admission progress',
      ),
    ),
    const SizedBox(height: AppSpacing.space5),
    // M1: named steps (recognition over recall): where you are, what is done,
    // what comes next. Decorative for screen readers: the heading above
    // already says "Step N of 4 · Title".
    ExcludeSemantics(
      child: _StepIndicator(titles: _titles, current: _step),
    ),
    const SizedBox(height: AppSpacing.space6),
    if (_error != null) ...[
      InlineAlert(tone: InlineAlertTone.danger, message: _error!),
      const SizedBox(height: AppSpacing.space4),
    ],
    // M1: the step's fields grouped in one card; navigation stays below it.
    // A Material surface (not a coloured box) so the switch and list tiles
    // inside keep their ink/ripple feedback.
    Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: t.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _stepBody(t),
        ),
      ),
    ),
    const SizedBox(height: AppSpacing.space8),
    Row(
      children: [
        if (_step > 0)
          Expanded(
            child: AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: _busy ? null : () => setState(() => _step--),
            ),
          ),
        if (_step > 0) const SizedBox(width: AppSpacing.space4),
        Expanded(
          child: AppButton(
            key: const Key('admit-next'),
            label: _step == _titles.length - 1
                ? (_busy
                      ? 'Saving…'
                      : (_progress.started ? 'Retry' : 'Admit learner'))
                : 'Next',
            onPressed: _busy || !_canAdvance
                ? null
                : () => _step == _titles.length - 1
                      ? _submit()
                      : setState(() => _step++),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _stepBody(SmartEmsTokens t) {
    // Once the learner exists, its identity fields are locked: a retry must not
    // silently describe a different person.
    final locked = _progress.started;
    switch (_step) {
      case 0:
        return [
          AppTextField(
            key: const Key('admit-first'),
            label: 'First name',
            required: true,
            value: _draft.firstName,
            state: locked
                ? AppTextFieldState.disabled
                : AppTextFieldState.normal,
            onChanged: (v) => setState(() => _draft.firstName = v),
          ),
          const SizedBox(height: AppSpacing.space5),
          AppTextField(
            key: const Key('admit-last'),
            label: 'Last name',
            required: true,
            value: _draft.lastName,
            state: locked
                ? AppTextFieldState.disabled
                : AppTextFieldState.normal,
            onChanged: (v) => setState(() => _draft.lastName = v),
          ),
          const SizedBox(height: AppSpacing.space5),
          AppTextField(
            key: const Key('admit-number'),
            label: 'Admission number',
            required: true,
            value: _draft.admissionNumber,
            state: locked
                ? AppTextFieldState.disabled
                : AppTextFieldState.normal,
            onChanged: (v) => setState(() => _draft.admissionNumber = v),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            'Each admission number can be used once in the institution.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ];
      case 1:
        if (_setupError != null)
          return [
            InlineAlert(tone: InlineAlertTone.danger, message: _setupError!),
          ];
        final years = _campusYears;
        final sections = _yearSections;
        return [
          if (_campuses.length != 1) ...[
            _label(t, 'Campus'),
            Semantics(
              label: 'Campus',
              child: DropdownButton<String>(
                key: const Key('admit-campus'),
                isExpanded: true,
                value: _draft.campusId,
                hint: const Text('Choose a campus'),
                items: [
                  for (final c in _campuses)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: locked
                    ? null
                    : (v) => setState(() {
                        _draft.campusId = v;
                        _draft.academicYearId = null;
                        _draft.sectionId = null;
                        _preselectYear();
                      }),
              ),
            ),
            const SizedBox(height: AppSpacing.space5),
          ],
          _label(t, 'Academic year'),
          Semantics(
            label: 'Academic year',
            child: DropdownButton<String>(
              key: const Key('admit-year'),
              isExpanded: true,
              value: years.any((y) => y.id == _draft.academicYearId)
                  ? _draft.academicYearId
                  : null,
              hint: Text(
                years.isEmpty
                    ? 'No academic year on this campus yet'
                    : 'Choose a year',
              ),
              items: [
                for (final y in years)
                  DropdownMenuItem(
                    value: y.id,
                    child: Text(y.current ? '${y.name} (current)' : y.name),
                  ),
              ],
              onChanged: (v) => setState(() {
                _draft.academicYearId = v;
                _draft.sectionId = null;
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.space5),
          _label(t, 'Class and section'),
          Semantics(
            label: 'Class and section',
            child: DropdownButton<String>(
              key: const Key('admit-section'),
              isExpanded: true,
              value: sections.any((s) => s.id == _draft.sectionId)
                  ? _draft.sectionId
                  : null,
              hint: Text(
                sections.isEmpty
                    ? 'No sections in this year yet'
                    : 'Choose a section',
              ),
              items: [
                for (final s in sections)
                  DropdownMenuItem(value: s.id, child: Text(_sectionLabel(s))),
              ],
              onChanged: (v) => setState(() => _draft.sectionId = v),
            ),
          ),
          const SizedBox(height: AppSpacing.space5),
          AppTextField(
            key: const Key('admit-roll'),
            label: 'Roll number (optional)',
            value: _draft.rollNumber,
            onChanged: (v) => setState(() => _draft.rollNumber = v),
          ),
        ];
      case 2:
        return [
          SwitchListTile(
            key: const Key('admit-guardian-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Add a parent or guardian now'),
            subtitle: const Text('Adult learners can be admitted without one.'),
            value: _draft.addGuardian,
            onChanged: _progress.guardianAdded
                ? null
                : (v) => setState(() => _draft.addGuardian = v),
          ),
          if (_draft.addGuardian) ...[
            const SizedBox(height: AppSpacing.space4),
            AppTextField(
              key: const Key('admit-g-first'),
              label: 'Guardian first name',
              required: true,
              value: _draft.guardianFirstName,
              onChanged: (v) => setState(() => _draft.guardianFirstName = v),
            ),
            const SizedBox(height: AppSpacing.space5),
            AppTextField(
              key: const Key('admit-g-last'),
              label: 'Guardian last name',
              required: true,
              value: _draft.guardianLastName,
              onChanged: (v) => setState(() => _draft.guardianLastName = v),
            ),
            const SizedBox(height: AppSpacing.space5),
            _label(t, 'Relationship'),
            Semantics(
              label: 'Relationship',
              child: DropdownButton<String>(
                key: const Key('admit-relationship'),
                isExpanded: true,
                value: _draft.relationship,
                items: const [
                  DropdownMenuItem(value: 'father', child: Text('Father')),
                  DropdownMenuItem(value: 'mother', child: Text('Mother')),
                  DropdownMenuItem(value: 'guardian', child: Text('Guardian')),
                ],
                onChanged: (v) =>
                    setState(() => _draft.relationship = v ?? 'guardian'),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'A parent login can be created later from Add user.',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
        ];
      default:
        final campus =
            _campuses.where((c) => c.id == _draft.campusId).firstOrNull?.name ??
            '—';
        final year =
            _years
                .where((y) => y.id == _draft.academicYearId)
                .firstOrNull
                ?.name ??
            '—';
        return [
          _review(
            t,
            'Learner',
            '${_draft.firstName.trim()} ${_draft.lastName.trim()}',
          ),
          _review(t, 'Admission number', _draft.admissionNumber.trim()),
          _review(t, 'Campus', campus),
          _review(t, 'Academic year', year),
          _review(t, 'Class and section', _sectionLabelFor(_draft.sectionId)),
          if (_draft.rollNumber.trim().isNotEmpty)
            _review(t, 'Roll number', _draft.rollNumber.trim()),
          _review(
            t,
            'Guardian',
            _draft.addGuardian
                ? '${_draft.guardianFirstName.trim()} ${_draft.guardianLastName.trim()} (${_draft.relationship})'
                : 'None',
          ),
        ];
    }
  }

  Widget _label(SmartEmsTokens t, String text) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Text(
        text,
        style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
      ),
    ),
  );

  Widget _review(SmartEmsTokens t, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodyTeacher.copyWith(color: t.textPrimary),
          ),
        ),
      ],
    ),
  );
}

/// Named admission steps: done (tick), current (filled), upcoming (outline).
/// Below 420 px only the numbers are shown so four steps always fit.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.titles, required this.current});
  final List<String> titles;
  final int current;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, c) {
        final showLabels = c.maxWidth >= 420;
        return Row(
          children: [
            for (var i = 0; i < titles.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space2,
                    ),
                    color: i <= current ? t.primaryAccent : t.border,
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current
                          ? t.primaryAccent
                          : (i == current ? t.primaryAction : t.surface),
                      border: Border.all(
                        color: i <= current ? t.primaryAction : t.borderStrong,
                      ),
                    ),
                    child: i < current
                        ? Icon(Icons.check, size: 16, color: t.onPrimary)
                        : Text(
                            '${i + 1}',
                            style: AppTypography.fieldLabel.copyWith(
                              color: i == current
                                  ? t.onPrimary
                                  : t.textSecondary,
                            ),
                          ),
                  ),
                  if (showLabels) ...[
                    const SizedBox(width: AppSpacing.space3),
                    Text(
                      titles[i],
                      style: AppTypography.fieldLabel.copyWith(
                        color: i == current ? t.textPrimary : t.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

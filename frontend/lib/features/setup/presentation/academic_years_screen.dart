import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';
import 'setup_scaffold.dart';

/// Step 1: academic years.
///
/// **There is no "set current" control, and that is not an omission.**
/// Probed live 2026-09-24: `current` is ignored on create and on update, no
/// `set-current` route exists, and it is not derived from the dates either
/// (a year covering today came back false while an expired year stayed
/// true). So the screen explains who can change it rather than showing a
/// button that would do nothing (D-19).
class AcademicYearsScreen extends StatefulWidget {
  const AcademicYearsScreen({
    required this.repository,
    required this.campusId,
    super.key,
  });

  final SetupRepository repository;
  final String campusId;

  @override
  State<AcademicYearsScreen> createState() => AcademicYearsScreenState();
}

class AcademicYearsScreenState extends State<AcademicYearsScreen> {
  ScreenState<List<AcademicYear>> _state =
      const ScreenState<List<AcademicYear>>.loading();

  String _name = '';
  String _start = '';
  String _end = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state =
        ScreenState<List<AcademicYear>>.loading(previous: _state.data));
    try {
      final years = await widget.repository.loadYears();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<AcademicYear>>.data(years));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<AcademicYear>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  bool get _canSubmit =>
      _name.trim().isNotEmpty &&
      isIsoDate(_start) &&
      isIsoDate(_end) &&
      _start.compareTo(_end) < 0;

  Future<String?> _create() async {
    try {
      await widget.repository.createYear(
        campusId: widget.campusId,
        name: _name.trim(),
        startDate: _start.trim(),
        endDate: _end.trim(),
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _start = '';
        _end = '';
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The year could not be created.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Academic years',
      note: const InlineAlert(
        tone: InlineAlertTone.info,
        message: 'The current year is set by your system administrator and '
            'cannot be changed in the app yet. Years created here are '
            'available to use, but will not become the current one.',
      ),
      children: [
        CreatePanel(
          addLabel: 'Add an academic year',
          canSubmit: _canSubmit,
          onSubmit: _create,
          fields: [
            SetupField(
              label: 'Name',
              value: _name,
              placeholder: 'e.g. 2026-27',
              onChanged: (v) => setState(() => _name = v),
            ),
            SetupField(
              label: 'Starts',
              value: _start,
              placeholder: 'YYYY-MM-DD',
              onChanged: (v) => setState(() => _start = v),
            ),
            SetupField(
              label: 'Ends',
              value: _end,
              placeholder: 'YYYY-MM-DD',
              onChanged: (v) => setState(() => _end = v),
            ),
            if (!_canSubmit &&
                (_start.isNotEmpty || _end.isNotEmpty) &&
                !(isIsoDate(_start) && isIsoDate(_end)))
              Text(
                'Dates must be written as YYYY-MM-DD.',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              )
            else if (isIsoDate(_start) &&
                isIsoDate(_end) &&
                _start.compareTo(_end) >= 0)
              Text(
                'The end date must be after the start date.',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<AcademicYear>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No academic years yet',
            emptyMessage:
                'Add the year the school is running. Sections, timetables '
                'and enrolments all belong to one.',
            emptyIcon: Icons.event_note_outlined,
            data: (context, years) => ListView(
              children: [
                for (final y in years)
                  SetupRow(
                    title: y.name,
                    detail: y.rangeLabel,
                    trailing: y.current ? 'Current' : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `YYYY-MM-DD`, the only shape these endpoints accept.
///
/// Checked in the client because the backend answers a malformed date with a
/// generic failure, and an admin mid-onboarding cannot act on that.
bool isIsoDate(String value) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value.trim());

/// Height given to a list that sits inside the scrolling setup page.
///
/// The page scrolls, so a list needs a bounded height; tying it to the
/// viewport keeps it honest at 360px and at 2× text without inventing a
/// magic number.
double setupListHeight(BuildContext context) =>
    MediaQuery.sizeOf(context).height * 0.6;

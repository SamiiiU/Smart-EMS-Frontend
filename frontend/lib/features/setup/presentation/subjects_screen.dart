import 'package:flutter/material.dart';

import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';
import 'academic_years_screen.dart' show setupListHeight;
import 'setup_scaffold.dart';

/// Step 4: subjects. School-wide, no year and no class — the simplest
/// screen in the batch, and deliberately left that way.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({required this.repository, super.key});

  final SetupRepository repository;

  @override
  State<SubjectsScreen> createState() => SubjectsScreenState();
}

class SubjectsScreenState extends State<SubjectsScreen> {
  ScreenState<List<Subject>> _state =
      const ScreenState<List<Subject>>.loading();

  String _name = '';
  String _code = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() =>
        _state = ScreenState<List<Subject>>.loading(previous: _state.data));
    try {
      final subjects = await widget.repository.loadSubjects();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<Subject>>.data(subjects));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Subject>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<String?> _create() async {
    try {
      await widget.repository.createSubject(
        name: _name.trim(),
        code: _code.trim().isEmpty ? null : _code.trim(),
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _code = '';
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The subject could not be created.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      title: 'Subjects',
      children: [
        CreatePanel(
          addLabel: 'Add a subject',
          canSubmit: _name.trim().isNotEmpty,
          onSubmit: _create,
          fields: [
            SetupField(
              label: 'Name',
              value: _name,
              placeholder: 'e.g. Mathematics',
              onChanged: (v) => setState(() => _name = v),
            ),
            SetupField(
              label: 'Code (optional)',
              value: _code,
              placeholder: 'e.g. MATH',
              onChanged: (v) => setState(() => _code = v),
            ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Subject>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No subjects yet',
            emptyMessage:
                'Add the subjects taught here. They are used for teaching '
                'assignments, the timetable and the diary.',
            emptyIcon: Icons.menu_book_outlined,
            data: (context, subjects) => ListView(
              children: [
                for (final s in subjects)
                  SetupRow(title: s.name, detail: s.code),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

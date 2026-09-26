import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/setup_repository.dart';
import '../domain/setup_models.dart';
import 'academic_years_screen.dart' show setupListHeight;
import 'setup_scaffold.dart';

/// Step 2: classes.
///
/// `levelOrder` is a visible field, not a hidden one, because it is what
/// keeps Class 10 below Class 2 — alphabetical order gets that wrong and
/// every school notices. The list is sorted by it (see [sortClasses]).
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({
    required this.repository,
    required this.campusId,
    super.key,
  });

  final SetupRepository repository;
  final String campusId;

  @override
  State<ClassesScreen> createState() => ClassesScreenState();
}

class ClassesScreenState extends State<ClassesScreen> {
  ScreenState<List<SchoolClass>> _state =
      const ScreenState<List<SchoolClass>>.loading();

  String _name = '';
  String _order = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state =
        ScreenState<List<SchoolClass>>.loading(previous: _state.data));
    try {
      final classes = await widget.repository.loadClasses();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<SchoolClass>>.data(classes));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<SchoolClass>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  bool get _orderValid =>
      _order.trim().isEmpty || int.tryParse(_order.trim()) != null;

  Future<String?> _create() async {
    try {
      await widget.repository.createClass(
        campusId: widget.campusId,
        name: _name.trim(),
        levelOrder: int.tryParse(_order.trim()),
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _order = '';
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The class could not be created.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SetupScaffold(
      title: 'Classes',
      note: const InlineAlert(
        tone: InlineAlertTone.info,
        message: 'Order decides how classes are listed everywhere in the '
            'app — 1 for the youngest. Without it, Class 10 sorts before '
            'Class 2.',
      ),
      children: [
        CreatePanel(
          addLabel: 'Add a class',
          canSubmit: _name.trim().isNotEmpty && _orderValid,
          onSubmit: _create,
          fields: [
            SetupField(
              label: 'Name',
              value: _name,
              placeholder: 'e.g. Class 9',
              onChanged: (v) => setState(() => _name = v),
            ),
            SetupField(
              label: 'Order (optional)',
              value: _order,
              placeholder: 'e.g. 9',
              onChanged: (v) => setState(() => _order = v),
            ),
            if (!_orderValid)
              Text(
                'Order must be a whole number.',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.textSecondary),
              ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<SchoolClass>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No classes yet',
            emptyMessage:
                'Add the classes this school teaches, such as Class 1 to '
                'Class 10.',
            emptyIcon: Icons.school_outlined,
            data: (context, classes) => ListView(
              children: [
                for (final c in classes)
                  SetupRow(
                    title: c.name,
                    detail: c.levelOrder == null
                        ? 'No order set'
                        : 'Order ${c.levelOrder}',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

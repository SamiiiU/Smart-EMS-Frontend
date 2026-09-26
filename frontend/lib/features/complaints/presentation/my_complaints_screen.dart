import 'package:flutter/material.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/academic_years_screen.dart'
    show setupListHeight;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/complaints_repository.dart';
import '../domain/complaint_models.dart';
import 'complaint_detail_screen.dart';
import 'complaint_row.dart';
import 'raise_complaint_screen.dart';

/// Screen 2: the complainant's own view — parent, teacher or student.
///
/// Sorted by what is unresolved (D-15): a person opens this to find out
/// whether anything has happened, and a resolved complaint from March should
/// not sit above one raised on Monday that nobody has touched.
///
/// Anonymous complaints deliberately do NOT appear here. They cannot — the
/// backend keeps no link to the raiser, which is exactly what makes them
/// anonymous. The screen says so rather than leaving someone hunting for one.
class MyComplaintsScreen extends StatefulWidget {
  const MyComplaintsScreen({
    required this.repository,
    this.campusId,
    super.key,
  });

  final ComplaintsRepository repository;

  /// Pre-resolved campus, for tests. Left null in the app, which resolves
  /// it once on load — see [ComplaintsRepository.resolveCampusId].
  final String? campusId;

  @override
  State<MyComplaintsScreen> createState() => MyComplaintsScreenState();
}

class MyComplaintsScreenState extends State<MyComplaintsScreen> {
  ScreenState<List<Complaint>> _state =
      const ScreenState<List<Complaint>>.loading();

  final DateTime _today = DateTime.now();

  /// Resolved once, because a parent cannot discover one at all and the
  /// screen has to say so rather than offering a form that cannot submit.
  String? _campusId;
  bool _campusResolved = false;

  @override
  void initState() {
    super.initState();
    _campusId = widget.campusId;
    _campusResolved = widget.campusId != null;
    load();
  }

  Future<void> load() async {
    setState(() =>
        _state = ScreenState<List<Complaint>>.loading(previous: _state.data));
    try {
      final rows = await widget.repository.loadMine();
      if (!_campusResolved) {
        _campusId = await widget.repository.resolveCampusId();
        _campusResolved = true;
      }
      if (!mounted) return;
      setState(() =>
          _state = ScreenState<List<Complaint>>.data(sortForOwner(rows, _today)));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<Complaint>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final campusId = _campusId;

    return SetupScaffold(
      title: 'My complaints',
      children: [
        if (campusId == null)
          // Not a failure to hide behind a spinner, and not a form that
          // cannot submit: a parent account genuinely cannot raise one
          // through this system today (open item 39).
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'Complaints cannot be raised from a parent account yet '
                '— the app has no way to tell the school which campus it '
                'belongs to. Please contact the school office directly. '
                'Anything already raised for you is shown below.',
          )
        else
          AppButton(
            label: 'Raise a complaint',
            icon: Icons.add,
            fullWidth: true,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RaiseComplaintScreen(
                    repository: widget.repository,
                    campusId: campusId,
                  ),
                ),
              );
              await load();
            },
          ),
        const SizedBox(height: AppSpacing.space5),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<Complaint>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nothing raised yet',
            emptyMessage: 'Complaints you send appear here with their status '
                'and any reply. Anything sent anonymously will not — there '
                'is no link back to you, which is what makes it anonymous.',
            emptyIcon: Icons.forum_outlined,
            data: (context, rows) => ListView(
              children: [
                for (final complaint in rows)
                  ComplaintRow(
                    complaint: complaint,
                    today: _today,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ComplaintDetailScreen(
                            repository: widget.repository,
                            complaintId: complaint.id,
                          ),
                        ),
                      );
                      await load();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

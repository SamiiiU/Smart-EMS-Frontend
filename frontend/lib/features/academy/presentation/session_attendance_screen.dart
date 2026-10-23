import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/states/loading_skeleton.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states/empty_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

Future<bool> _deviceOnline() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}

/// Attendance for ONE dated batch session.
///
/// ONLINE-ONLY in v1: this screen never touches the school offline queue or
/// roster cache. When offline, submission is disabled and says why.
///
/// Records are per (session, learner), so Maths and Physics on the same day
/// are independent. Each changed row gets a clientUuid that is kept until
/// the server confirms that row; a retry after a lost response reuses it and
/// the server answers "replayed" instead of recording twice. A row is shown
/// as saved only when the server said recorded/replayed for it.
class SessionAttendanceScreen extends StatefulWidget {
  const SessionAttendanceScreen({
    required this.repository,
    required this.session,
    required this.title,
    this.isOnline,
    super.key,
  });
  final AcademyRepository repository;
  final Session session;
  final String title;

  /// Injectable for tests; defaults to the device connectivity check.
  final Future<bool> Function()? isOnline;

  @override
  State<SessionAttendanceScreen> createState() =>
      _SessionAttendanceScreenState();
}

class _SessionAttendanceScreenState extends State<SessionAttendanceScreen> {
  ScreenState<AttendanceSheet> _state =
      const ScreenState<AttendanceSheet>.loading();
  bool _online = true;
  bool _saving = false;

  /// studentId → chosen status (only rows the user changed).
  final Map<String, String> _draft = {};

  /// studentId → (status, clientUuid) kept until the server confirms.
  final Map<String, ({String status, String clientUuid})> _pending = {};

  /// studentId → last server rejection text.
  final Map<String, String> _rowErrors = {};

  String? _banner;
  InlineAlertTone _bannerTone = InlineAlertTone.info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _checkOnline() async {
    final online = await (widget.isOnline ?? _deviceOnline)();
    if (mounted) setState(() => _online = online);
  }

  Future<void> _load() async {
    await _checkOnline();
    setState(
      () =>
          _state = ScreenState<AttendanceSheet>.loading(previous: _state.data),
    );
    try {
      final sheet = await widget.repository.sheet(widget.session.id);
      if (!mounted) return;
      setState(() => _state = ScreenState<AttendanceSheet>.data(sheet));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(
        () => _state = ScreenState<AttendanceSheet>.failed(
          LoadFailure(
            message: AcademyRepository.explain(f),
            kind: f.kind,
            unreachable: f.unreachable,
          ),
          cached: _state.data,
          connection: f.unreachable
              ? NetworkStatus.offline
              : NetworkStatus.online,
        ),
      );
    }
  }

  void _choose(String studentId, String status) {
    setState(() {
      _draft[studentId] = status;
      // A different choice is a different operation: drop any unconfirmed id.
      if (_pending[studentId]?.status != status) _pending.remove(studentId);
      _rowErrors.remove(studentId);
    });
  }

  Future<void> _submit() async {
    if (_saving || _draft.isEmpty) return;
    await _checkOnline();
    if (!_online) {
      setState(() {
        _banner =
            'You are offline. Academy attendance is online-only in this version — nothing was saved. Reconnect and submit again.';
        _bannerTone = InlineAlertTone.warning;
      });
      return;
    }
    setState(() {
      _saving = true;
      _banner = null;
    });
    final rows = {
      for (final e in _draft.entries)
        e.key: _pending.putIfAbsent(
          e.key,
          () => (status: e.value, clientUuid: widget.repository.newKey()),
        ),
    };
    try {
      final results = await widget.repository.mark(widget.session.id, rows);
      if (!mounted) return;
      final byStudent = {for (final r in results) r.studentId: r};
      var saved = 0;
      setState(() {
        for (final id in rows.keys) {
          final r = byStudent[id];
          if (r != null && r.saved) {
            saved++;
            _draft.remove(id);
            _pending.remove(id);
            _rowErrors.remove(id);
          } else {
            _rowErrors[id] =
                r?.message ?? 'No answer for this learner — submit again.';
          }
        }
        final failed = rows.length - saved;
        _banner = failed == 0
            ? 'Saved $saved ${saved == 1 ? 'mark' : 'marks'}.'
            : 'Saved $saved; $failed not saved — see the highlighted learners.';
        _bannerTone = failed == 0
            ? InlineAlertTone.success
            : InlineAlertTone.danger;
      });
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      final unreachable = e is LoadFailure && e.unreachable;
      setState(() {
        // Pending ids are KEPT: resubmitting replays rather than duplicates.
        _banner = unreachable
            ? 'The connection dropped. It is not known whether these marks were saved — submit again; the server will not record them twice.'
            : AcademyRepository.explain(e, 'Attendance was not saved.');
        _bannerTone = InlineAlertTone.danger;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.session;
    final future = DateTime.tryParse(s.date)?.isAfter(DateTime.now()) ?? false;
    return Scaffold(
      backgroundColor: context.tokens.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const BackButton(),
                Expanded(
                  child: PageHeader(
                    title: widget.title,
                    subtitle:
                        'Session ${s.date} · ${s.start}–${s.end}${s.room == null ? '' : ' · ${s.room}'}',
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_online)
                    const InlineAlert(
                      tone: InlineAlertTone.warning,
                      icon: Icons.cloud_off_outlined,
                      message:
                          'Offline. Academy attendance is online-only in this version, so it cannot be submitted until you reconnect. '
                          'School attendance offline saving is not used for academy sessions.',
                    ),
                  if (future)
                    const InlineAlert(
                      tone: InlineAlertTone.info,
                      message:
                          'This session is in the future; attendance can be marked on or after its date.',
                    ),
                  if (_banner != null) ...[
                    const SizedBox(height: AppSpacing.space4),
                    InlineAlert(tone: _bannerTone, message: _banner!),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  final sheet = _state.data;
                  if (sheet == null) {
                    if (_state.status == ScreenStatus.error) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _state.failure?.message ??
                                  'Could not load the session.',
                            ),
                            const SizedBox(height: AppSpacing.space5),
                            AppButton(label: 'Try again', onPressed: _load),
                          ],
                        ),
                      );
                    }
                    return const LoadingSkeleton.listRows(count: 5);
                  }
                  if (sheet.learners.isEmpty) {
                    return const EmptyState(
                      icon: Icons.groups_outlined,
                      title: 'No learners are enrolled in this batch.',
                      message:
                          'Enrol learners in the batch to take attendance for this session.',
                    );
                  }
                  final unmarked = [
                    for (final l in sheet.learners)
                      if (l.unmarked) l,
                  ];
                  final marked = [
                    for (final l in sheet.learners)
                      if (!l.unmarked) l,
                  ];
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.space6),
                    children: [
                      Text(
                        'Unmarked (${unmarked.length})',
                        style: AppTypography.sectionHeading.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                      if (unmarked.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.space4),
                          child: Text('Everyone has a mark.'),
                        ),
                      for (final l in unmarked) _row(l),
                      const SizedBox(height: AppSpacing.space6),
                      Text(
                        'Marked (${marked.length})',
                        style: AppTypography.sectionHeading.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                      for (final l in marked) _row(l),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: AppButton(
                key: const ValueKey('academy-attendance-submit'),
                label: _saving
                    ? 'Saving…'
                    : _draft.isEmpty
                    ? 'No changes'
                    : 'Submit ${_draft.length} ${_draft.length == 1 ? 'change' : 'changes'}',
                fullWidth: true,
                icon: _online ? Icons.check : Icons.cloud_off_outlined,
                onPressed:
                    _saving ||
                        _draft.isEmpty ||
                        !_online ||
                        future ||
                        s.cancelled
                    ? null
                    : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(SheetLearner l) {
    final t = context.tokens;
    final chosen = _draft[l.studentId] ?? (l.unmarked ? null : l.status);
    final error = _rowErrors[l.studentId];
    return Container(
      key: ValueKey('learner-${l.studentId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.space4),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: error != null ? t.dangerBg : t.surface,
        border: Border.all(
          color: _draft.containsKey(l.studentId) ? t.primaryAction : t.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.name,
                  style: AppTypography.personName.copyWith(
                    color: t.textPrimary,
                  ),
                ),
              ),
              StatusChip(
                _draft.containsKey(l.studentId) ? 'unsaved' : l.status,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              for (final status in attendanceStatuses)
                ChoiceChip(
                  label: Text(status[0].toUpperCase() + status.substring(1)),
                  selected: chosen == status,
                  onSelected: _saving
                      ? null
                      : (_) => _choose(l.studentId, status),
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.space3),
            Text(
              error,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.dangerTextOnBg,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

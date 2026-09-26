import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../../core/widgets/status_pill.dart';
import '../../admin/domain/people_models.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/complaints_repository.dart';
import '../domain/complaint_models.dart';

/// Screens 2b/4: one complaint — the thread, and (for staff) assignment and
/// resolution.
///
/// The same screen serves the complainant and the admin. It does not branch
/// on role to decide what to SHOW: the backend already filters internal
/// comments out of a complainant's response, so whatever arrives is what
/// that person is allowed to see. Branching here would mean the app was the
/// thing keeping the secret, which is exactly the arrangement T15's remarks
/// defect proved unreliable.
///
/// What [staffControls] changes is what can be DONE — assign, resolve, and
/// write an internal note.
class ComplaintDetailScreen extends StatefulWidget {
  const ComplaintDetailScreen({
    required this.repository,
    required this.complaintId,
    this.staffControls = false,
    this.staff = const [],
    super.key,
  });

  final ComplaintsRepository repository;
  final String complaintId;

  /// True for the admin worklist. Assignment and resolution only.
  final bool staffControls;

  /// Who a complaint can be assigned to. Empty disables assignment with a
  /// reason rather than an inert control.
  final List<PersonAccount> staff;

  @override
  State<ComplaintDetailScreen> createState() => ComplaintDetailScreenState();
}

class ComplaintDetailScreenState extends State<ComplaintDetailScreen> {
  ScreenState<Complaint> _state = const ScreenState<Complaint>.loading();
  List<ComplaintComment> _comments = const [];

  String _reply = '';
  bool _internal = false;
  bool _busy = false;
  String? _error;

  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(
        () => _state = ScreenState<Complaint>.loading(previous: _state.data));
    try {
      final complaint = await widget.repository.load(widget.complaintId);
      final comments =
          await widget.repository.loadComments(widget.complaintId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _state = ScreenState<Complaint>.data(complaint, isEmpty: false);
      });
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<Complaint>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.comment(
        id: widget.complaintId,
        body: _reply.trim(),
        isInternal: _internal,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reply = '';
        _internal = false;
      });
      await load();
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message ?? 'The reply could not be sent.';
      });
    }
  }

  Future<void> _setStatus(ComplaintStatus status) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.setStatus(id: widget.complaintId, status: status);
      if (!mounted) return;
      setState(() => _busy = false);
      await load();
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message ?? 'The status could not be changed.';
      });
    }
  }

  Future<void> _assign(PersonAccount person) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository
          .assign(id: widget.complaintId, staffId: person.id);
      if (!mounted) return;
      setState(() => _busy = false);
      await load();
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message ?? 'This could not be assigned.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      title: 'Complaint',
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: ScreenStateBuilder<Complaint>(
            state: _state,
            onRetry: load,
            emptyTitle: 'This complaint could not be opened',
            emptyMessage: 'It could not be read. Reopen this screen to try '
                'again — if it keeps happening, tell your system '
                'administrator.',
            data: _body,
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Complaint complaint) {
    final t = context.tokens;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(
          complaint.subject,
          style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(status: complaint.status.pill, size: StatusPillSize.sm),
            Text(
              complaint.status.label,
              style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
            ),
            Text(
              complaint.categoryLabel,
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
            ),
            if (complaint.isOverdue(_today))
              Text(
                'Overdue',
                style: AppTypography.bodyAdminMeta
                    .copyWith(color: t.dangerTextOnBg),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.space5),

        if (complaint.isAnonymous)
          const InlineAlert(
            tone: InlineAlertTone.warning,
            message: 'Sent anonymously. There is no record of who raised it, '
                'so nobody can reply to them directly — anything written '
                'here will not reach them.',
          ),
        const SizedBox(height: AppSpacing.space4),

        Container(
          padding: const EdgeInsets.all(AppSpacing.space5),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: t.border, width: AppSizing.borderThin),
          ),
          child: Text(
            complaint.description,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
          ),
        ),

        if (complaint.resolutionNote != null &&
            complaint.resolutionNote!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.space5),
          InlineAlert(
            tone: InlineAlertTone.success,
            message: 'Resolution: ${complaint.resolutionNote}',
          ),
        ],

        const SizedBox(height: AppSpacing.space6),
        Text(
          'Replies',
          style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space4),

        if (_comments.isEmpty)
          Text(
            'Nothing yet.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          )
        else
          for (final comment in _comments) CommentBubble(comment: comment),

        const SizedBox(height: AppSpacing.space6),

        if (_error != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          const SizedBox(height: AppSpacing.space4),
        ],

        if (!complaint.status.isFinished) ...[
          AppTextField(
            label: 'Write a reply',
            value: _reply,
            onChanged: (v) => setState(() => _reply = v),
          ),
          if (widget.staffControls) ...[
            const SizedBox(height: AppSpacing.space4),
            InternalToggle(
              internal: _internal,
              onChanged: (v) => setState(() => _internal = v),
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          AppButton(
            label: _busy ? 'Sending…' : 'Send reply',
            fullWidth: true,
            onPressed: _busy || _reply.trim().isEmpty ? null : _send,
          ),
        ],

        if (widget.staffControls) ...[
          const SizedBox(height: AppSpacing.space8),
          Text(
            'Assign',
            style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space3),
          if (widget.staff.isEmpty)
            Text(
              'No staff records to assign this to.',
              style:
                  AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
            )
          else
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final person in widget.staff)
                  PickerChip(
                    label: person.fullName,
                    selected: complaint.assignedToStaffId == person.id,
                    onTap: _busy ? () {} : () => _assign(person),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.space6),
          Text(
            'Move it on',
            style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            // `open` is rejected by the backend, so it is never offered —
            // a complaint cannot be un-resolved.
            'A complaint cannot be moved back to open once it has been '
            'changed.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final status in ComplaintStatus.settable)
                PickerChip(
                  label: status.label,
                  selected: complaint.status == status,
                  onTap: _busy ? () {} : () => _setStatus(status),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One entry on the thread.
///
/// An internal note is marked **unmistakably** — its own tint, its own
/// border and a label in words — because the person writing the next one
/// needs to know at a glance whether the complainant is reading along.
class CommentBubble extends StatelessWidget {
  const CommentBubble({required this.comment, super.key});

  final ComplaintComment comment;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final internal = comment.isInternal;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: internal ? t.warningBg : t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: internal ? t.warning : t.border,
          width: internal ? AppSizing.borderThick : AppSizing.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (internal) ...[
            // Words, not just a colour — the whole point is that this is
            // never mistaken for something the complainant can read.
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: AppSizing.statusGlyphMd,
                  color: t.warningTextOnBg,
                ),
                const SizedBox(width: AppSpacing.space2),
                Expanded(
                  child: Text(
                    'Internal note — the complainant cannot see this',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.warningTextOnBg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
          ],
          Text(
            comment.body,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            comment.createdAt,
            style: AppTypography.timestamp.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The internal-note toggle, with the consequence beside it.
class InternalToggle extends StatelessWidget {
  const InternalToggle({
    required this.internal,
    required this.onChanged,
    super.key,
  });

  final bool internal;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: internal ? t.warningBg : t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: internal ? t.warning : t.border,
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
                  'Internal note',
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
              ),
              Semantics(
                label: 'Make this an internal note',
                toggled: internal,
                child: Switch.adaptive(value: internal, onChanged: onChanged),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            internal
                ? 'Staff only. The person who raised this will not see it.'
                : 'The person who raised this will see your reply.',
            style: AppTypography.bodyAdminMeta.copyWith(
              color: internal ? t.warningTextOnBg : t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

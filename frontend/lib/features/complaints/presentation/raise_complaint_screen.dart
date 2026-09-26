import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/complaints_repository.dart';
import '../domain/complaint_models.dart';

/// Screen 1: raise a complaint. Parent, teacher and student.
///
/// ## Anonymity is stated honestly, at the moment of choosing
///
/// Anonymous here is REAL: the backend stores no `raised_by_user_id` at all,
/// so not even an administrator can trace it. The consequence of that is
/// what matters to the person choosing — **nobody can reply to them** — and
/// it is said next to the control, before submitting, not after.
///
/// A parent who expects an answer and gets silence is worse served than one
/// who was told the trade before they made it.
class RaiseComplaintScreen extends StatefulWidget {
  const RaiseComplaintScreen({
    required this.repository,
    required this.campusId,
    super.key,
  });

  final ComplaintsRepository repository;
  final String campusId;

  @override
  State<RaiseComplaintScreen> createState() => RaiseComplaintScreenState();
}

class RaiseComplaintScreenState extends State<RaiseComplaintScreen> {
  ComplaintCategory _category = ComplaintCategory.academic;
  ComplaintPriority _priority = ComplaintPriority.medium;
  String _subject = '';
  String _description = '';
  bool _anonymous = false;

  bool _busy = false;
  String? _error;
  bool _sent = false;

  bool get _canSubmit =>
      !_busy && _subject.trim().isNotEmpty && _description.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.raise(
        campusId: widget.campusId,
        category: _category,
        subject: _subject.trim(),
        description: _description.trim(),
        priority: _priority,
        isAnonymous: _anonymous,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.message ?? 'This could not be sent.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (_sent) {
      return SetupScaffold(
        title: 'Raise a complaint',
        children: [
          InlineAlert(
            tone: InlineAlertTone.success,
            message: _anonymous
                ? 'Sent anonymously. The school will see it, but they cannot '
                    'reply to you and you will not get an update.'
                : 'Sent. You can follow it under “My complaints”.',
          ),
        ],
      );
    }

    return SetupScaffold(
      title: 'Raise a complaint',
      children: [
        CreatePanel(
          addLabel: 'Write your complaint',
          canSubmit: _canSubmit,
          onSubmit: () async {
            await _submit();
            return _error;
          },
          fields: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What is it about',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final c in ComplaintCategory.values)
                        PickerChip(
                          label: c.label,
                          selected: _category == c,
                          onTap: () => setState(() => _category = c),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SetupField(
              label: 'Subject',
              value: _subject,
              placeholder: 'One line — what happened',
              onChanged: (v) => setState(() => _subject = v),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: AppTextField(
                label: 'Details',
                value: _description,
                placeholder: 'What happened, when, and who was involved',
                onChanged: (v) => setState(() => _description = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How urgent',
                    style: AppTypography.fieldLabel
                        .copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final p in ComplaintPriority.values)
                        PickerChip(
                          label: p.label,
                          selected: _priority == p,
                          onTap: () => setState(() => _priority = p),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            AnonymityControl(
              anonymous: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
            ),
          ],
        ),
      ],
    );
  }
}

/// The anonymity control, with its consequence beside it.
///
/// Not a bare "Send anonymously" switch: the thing the person needs to weigh
/// is not the label but what they give up, so both states spell it out.
class AnonymityControl extends StatelessWidget {
  const AnonymityControl({
    required this.anonymous,
    required this.onChanged,
    super.key,
  });

  final bool anonymous;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: anonymous ? t.warningBg : t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: anonymous ? t.warning : t.border,
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
                  'Send without my name',
                  style:
                      AppTypography.personName.copyWith(color: t.textPrimary),
                ),
              ),
              Semantics(
                label: 'Send this complaint without my name',
                toggled: anonymous,
                child: Switch.adaptive(
                  value: anonymous,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            anonymous
                // The cost, before the choice is made.
                ? 'The school will not know who sent this — and because of '
                    'that, nobody can reply to you. You will not see an '
                    'update, and it will not appear in “My complaints”.'
                : 'The school will see your name and can reply to you. You '
                    'can follow this under “My complaints”.',
            style: AppTypography.bodyAdminMeta.copyWith(
              color: anonymous ? t.warningTextOnBg : t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

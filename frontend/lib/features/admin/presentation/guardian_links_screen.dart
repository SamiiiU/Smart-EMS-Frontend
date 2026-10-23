import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/states/empty_state.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/admin_repository.dart';

const _browseCategories = ['academic', 'attendance', 'finance', 'documents'];
const _allCategories = [..._browseCategories, 'communication'];

/// Staff-facing wording for server link statuses; unknown values are shown as received.
String guardianLinkStatusLabel(Object? status) => switch (status) {
  'unreviewed' => 'Awaiting review',
  'active' => 'Verified',
  'suspended' => 'Suspended',
  'revoked' => 'Revoked',
  'rejected' => 'Verification rejected',
  null => 'Unknown',
  _ => status.toString(),
};

String _categoryLabel(String c) =>
    c == 'communication' ? 'Receive communications' : 'View $c';

String _instant(Object? iso) {
  final at = iso == null ? null : DateTime.tryParse('$iso');
  return at == null ? 'Not verified' : DateFormat.yMMMd().format(at.toLocal());
}

class GuardianLinksScreen extends StatefulWidget {
  const GuardianLinksScreen({
    required this.repository,
    required this.studentId,
    super.key,
  });
  final AdminRepository repository;
  final String studentId;
  @override
  State<GuardianLinksScreen> createState() => _GuardianLinksScreenState();
}

class _GuardianLinksScreenState extends State<GuardianLinksScreen> {
  List<Map<String, dynamic>>? _links;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _links = null;
      _error = null;
    });
    try {
      final links = await widget.repository.loadGuardianLinks(widget.studentId);
      if (mounted) {
        setState(() => _links = links);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is LoadFailure
              ? e.message ?? 'Guardian review unavailable.'
              : 'Guardian review unavailable.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review(Map<String, dynamic> link) async {
    final decision = await showDialog<GuardianReviewDecision>(
      context: context,
      builder: (_) => GuardianReviewDialog(
        guardianName: '${link['first_name']} ${link['last_name']}',
        allowReject: link['link_status'] == 'unreviewed',
      ),
    );
    // null = cancelled: nothing is sent.
    if (decision == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.reviewGuardianLink(
        link['id'] as String,
        status: decision.status,
        reason: decision.reason,
        categories: decision.status == 'active' ? decision.grants : null,
      );
      if (mounted) {
        await _load();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _links = null;
          _error = e is LoadFailure
              ? e.message ?? 'Review not confirmed. Refresh before retrying.'
              : 'Review not confirmed. Refresh before retrying.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.space5);
    return SetupScaffold(
      title: 'Guardian access',
      note: const Text(
        'Pending relationships have no child-data access. Each verified relationship has separate '
        'categories. Revocation takes effect for new reads and deliveries.',
      ),
      children: [
        if (_busy) ...[
          Semantics(
            liveRegion: true,
            label: 'Loading guardian relationships',
            child: const LinearProgressIndicator(),
          ),
          gap,
        ],
        if (_error != null) ...[
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          gap,
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: 'Refresh relationships',
            icon: Icons.refresh,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: _busy ? null : _load,
          ),
        ),
        gap,
        if (_links != null && _links!.isEmpty)
          const EmptyState(
            icon: Icons.family_restroom_outlined,
            title: 'No guardian relationships recorded',
            message:
                'Relationships added for this student appear here for review.',
          ),
        for (final link in _links ?? <Map<String, dynamic>>[]) ...[
          _LinkCard(link: link, busy: _busy, onReview: () => _review(link)),
          const SizedBox(height: AppSpacing.space4),
        ],
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.link,
    required this.busy,
    required this.onReview,
  });
  final Map<String, dynamic> link;
  final bool busy;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = link['link_status'];
    final active = status == 'active';
    final name = '${link['first_name']} ${link['last_name']}';
    final allowed = [
      for (final c in _allCategories)
        if (active && link['can_view_$c'] == true) c,
    ];
    final contactOnly =
        active && !_browseCategories.any((c) => link['can_view_$c'] == true);
    final meta = AppTypography.fieldLabel.copyWith(color: t.textSecondary);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(name, style: AppTypography.cardHeading),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text('Status: ${guardianLinkStatusLabel(status)}', style: meta),
          if (link['is_emergency_contact'] == true)
            Text('Emergency contact', style: meta),
          Text('Verified: ${_instant(link['verified_at'])}', style: meta),
          if (active && !contactOnly) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Allowed: ${allowed.map(_categoryLabel).join(', ')}',
              style: AppTypography.bodyTeacher,
            ),
          ],
          if (contactOnly) ...[
            const SizedBox(height: AppSpacing.space2),
            const InlineAlert(
              tone: InlineAlertTone.info,
              message: 'Contact only - no protected browsing',
            ),
          ],
          if (!['revoked', 'rejected'].contains(status)) ...[
            const SizedBox(height: AppSpacing.space5),
            AppButton(
              label: 'Review relationship',
              semanticsLabel: 'Review relationship with $name',
              variant: AppButtonVariant.secondary,
              onPressed: busy ? null : onReview,
            ),
          ],
        ],
      ),
    );
  }
}

/// The review outcome sent to the server; categories only matter for 'active'.
class GuardianReviewDecision {
  const GuardianReviewDecision(this.status, this.reason, this.grants);
  final String status;
  final String reason;
  final Map<String, bool> grants;
}

/// Review dialog. Rules unchanged: explicit categories (all off by default), a
/// non-blank evidence/decision reason (max 500), and "reject" only while unreviewed.
class GuardianReviewDialog extends StatefulWidget {
  const GuardianReviewDialog({
    required this.guardianName,
    required this.allowReject,
    super.key,
  });
  final String guardianName;
  final bool allowReject;
  @override
  State<GuardianReviewDialog> createState() => _GuardianReviewDialogState();
}

class _GuardianReviewDialogState extends State<GuardianReviewDialog> {
  String _status = 'active', _reason = '';
  bool _attempted = false;
  final _grants = <String, bool>{for (final c in _allCategories) c: false};

  void _record() {
    final reason = _reason.trim();
    if (reason.isEmpty) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(
      context,
    ).pop(GuardianReviewDecision(_status, reason, Map.of(_grants)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final missing = _attempted && _reason.trim().isEmpty;
    final reasonLabel = _status == 'active'
        ? 'Verification evidence reference'
        : 'Decision reason';
    return AlertDialog(
      title: Text('Review ${widget.guardianName}'),
      content: SizedBox(
        width: math.min(440.0, MediaQuery.sizeOf(context).width - 80),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Verify the relationship independently. Emergency contact status alone grants no '
                'browsing. Do not enter sensitive custody details here.',
              ),
              const SizedBox(height: AppSpacing.space5),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Decision'),
                items: [
                  const DropdownMenuItem(
                    value: 'active',
                    child: Text('Verify with explicit categories'),
                  ),
                  const DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspend'),
                  ),
                  const DropdownMenuItem(
                    value: 'revoked',
                    child: Text('Revoke'),
                  ),
                  if (widget.allowReject)
                    const DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Reject verification'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              if (_status == 'active') ...[
                const SizedBox(height: AppSpacing.space4),
                Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final category in _allCategories)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _categoryLabel(category),
                            style: AppTypography.bodyTeacher,
                          ),
                          value: _grants[category]!,
                          onChanged: (value) =>
                              setState(() => _grants[category] = value),
                        ),
                    ],
                  ),
                ),
                Text(
                  'Leave every browsing category off for a contact-only relationship.',
                  style: AppTypography.caption.copyWith(color: t.textSecondary),
                ),
              ],
              if (_status == 'revoked' || _status == 'rejected') ...[
                const SizedBox(height: AppSpacing.space4),
                InlineAlert(
                  tone: InlineAlertTone.warning,
                  message: _status == 'revoked'
                      ? 'Revoking removes this guardian\'s access to the child. It cannot be reviewed again here.'
                      : 'Rejecting closes this verification request. It cannot be reviewed again here.',
                ),
              ],
              const SizedBox(height: AppSpacing.space5),
              AppTextField(
                key: const Key('guardian-review-reason'),
                label: reasonLabel,
                required: true,
                value: _reason,
                state: missing
                    ? AppTextFieldState.error
                    : AppTextFieldState.normal,
                errorText: missing
                    ? 'Enter a ${reasonLabel.toLowerCase()} to record this review.'
                    : null,
                onChanged: (v) => setState(
                  () => _reason = v.length > 500 ? v.substring(0, 500) : v,
                ),
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Required, up to 500 characters. Saved with the review.',
                style: AppTypography.caption.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.space3,
          runSpacing: AppSpacing.space3,
          children: [
            AppButton(
              key: const Key('guardian-review-cancel'),
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              key: const Key('guardian-review-record'),
              label: 'Record review',
              onPressed: _record,
            ),
          ],
        ),
      ],
    );
  }
}

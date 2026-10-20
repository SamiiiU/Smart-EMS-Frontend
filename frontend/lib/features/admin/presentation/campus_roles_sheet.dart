import 'package:flutter/material.dart';

import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/states/loading_skeleton.dart';

import '../../../core/widgets/confirm_dialog.dart';

import '../../../core/shell/campus_context.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/admin_repository.dart';

/// Overhaul: campus roles for one staff account (ADR-011 campus delegation),
/// previously reachable only through the API. The server decides who may grant
/// which role on which campus; its refusal is shown verbatim.
Future<void> showCampusRolesSheet(
  BuildContext context, {
  required AdminRepository repository,
  required String userId,
  required String personName,
  required List<CampusOption> campuses,
  Set<String>? allowedRoles,
  Set<String>? allowedCampusIds,
}) => showAppSheet<void>(
  context,
  title: 'Campus roles',
  // The shared frame moves focus into the sheet (DLG-1), names the Close
  // button and keeps the actions above the keyboard.
  builder: (_) => CampusRolesSheet(
    repository: repository,
    userId: userId,
    personName: personName,
    campuses: campuses,
    allowedRoles: allowedRoles,
    allowedCampusIds: allowedCampusIds,
  ),
);

class CampusRolesSheet extends StatefulWidget {
  const CampusRolesSheet({
    required this.repository,
    required this.userId,
    required this.personName,
    required this.campuses,
    this.allowedRoles,
    this.allowedCampusIds,
    super.key,
  });

  final AdminRepository repository;
  final String userId;
  final String personName;
  final List<CampusOption> campuses;

  /// Roles this viewer may grant (ADR-011: a campus admin only teacher and
  /// attendance staff). Null = every ordinary role, as before; the server
  /// decides either way.
  final Set<String>? allowedRoles;

  /// Campuses this viewer administers (a campus admin: those where its
  /// campus_admin grant carries user.manage). Null = all offered campuses.
  final Set<String>? allowedCampusIds;

  @override
  State<CampusRolesSheet> createState() => _CampusRolesSheetState();
}

class _CampusRolesSheetState extends State<CampusRolesSheet> {
  List<CampusRoleGrant>? _grants;
  String? _error;
  String? _notice;
  bool _busy = false;
  String? _campus;
  String _role = 'teacher';

  List<MapEntry<String, String>> get _roleOptions => [
    for (final e in campusRoleLabels.entries)
      if (widget.allowedRoles == null || widget.allowedRoles!.contains(e.key))
        e,
  ];

  List<CampusOption> get _campusOptions => [
    for (final c in widget.campuses)
      if (widget.allowedCampusIds == null ||
          widget.allowedCampusIds!.contains(c.id))
        c,
  ];

  /// Privileged target, from the server's own grant list: a campus_admin (or
  /// higher) role. CampusGrantService refuses grant/revoke for these
  /// ("Self and privileged account grants cannot be changed here"), so the
  /// sheet does not offer changes it knows will be refused. Institution-wide
  /// owner/admin roles are not in this list (campus grants only); for those
  /// the server's refusal is still shown verbatim.
  static const _privileged = {
    'campus_admin',
    'admin',
    'institution_admin',
    'owner',
    'institution_owner',
    'super_admin',
  };
  bool get _protectedTarget =>
      (_grants ?? const []).any((g) => _privileged.contains(g.role));

  @override
  void initState() {
    super.initState();
    final campuses = _campusOptions;
    if (campuses.length == 1) _campus = campuses.single.id;
    final roles = _roleOptions;
    if (roles.isNotEmpty && !roles.any((e) => e.key == _role)) {
      _role = roles.first.key;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final grants = await widget.repository.loadCampusRoles(widget.userId);
      if (mounted) setState(() => _grants = grants);
    } on LoadFailure catch (f) {
      if (mounted) {
        setState(
          () => _error = f.message ?? 'Campus roles could not be loaded.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      await _load();
      if (mounted) setState(() => _notice = success);
    } on LoadFailure catch (f) {
      if (mounted) {
        setState(() => _error = f.message ?? 'That change could not be saved.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CampusRoleGrant g) async {
    final label = campusRoleLabels[g.role] ?? g.role;
    final ok = await confirmAction(
      context,
      title: 'Remove this campus role?',
      message:
          '${widget.personName} will lose $label access at ${g.campusName} '
          'immediately. Other campuses are not affected.',
      confirmLabel: 'Remove',
      confirmKey: const Key('confirm-remove-campus-role'),
    );
    if (!ok) return;
    await _run(
      () => widget.repository.revokeCampusRole(widget.userId, g.grantId),
      '$label removed at ${g.campusName}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final grants = _grants;
    // Heading ("Campus roles"), named Close, focus, safe area, keyboard lift
    // and scrolling come from the shared AppSheetFrame (showAppSheet).
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.personName,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space6),
          if (_error != null) ...[
            InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            const SizedBox(height: AppSpacing.space4),
          ],
          if (_notice != null) ...[
            InlineAlert(tone: InlineAlertTone.info, message: _notice!),
            const SizedBox(height: AppSpacing.space4),
          ],
          if (grants == null && _error == null)
            const LoadingSkeleton.listRows(count: 3)
          else if (grants != null && grants.isEmpty)
            Text(
              'No campus roles yet.',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            )
          else if (grants != null)
            for (final g in grants)
              ListTile(
                key: Key('campus-role-${g.grantId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(campusRoleLabels[g.role] ?? g.role),
                subtitle: Text(g.campusName),
                trailing: _protectedTarget
                    ? null
                    : IconButton(
                        tooltip:
                            'Remove ${campusRoleLabels[g.role] ?? g.role} at ${g.campusName}',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _busy ? null : () => _remove(g),
                      ),
              ),
          if (_protectedTarget) ...[
            const SizedBox(height: AppSpacing.space4),
            const InlineAlert(
              key: Key('campus-roles-protected'),
              tone: InlineAlertTone.info,
              message:
                  'This account holds an administrative role, so its campus roles '
                  'cannot be changed here.',
            ),
          ] else ...[
            const Divider(height: AppSpacing.space8),
            Text(
              'Add a campus role',
              style: AppTypography.sectionHeading.copyWith(
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            Semantics(
              label: 'Campus',
              child: DropdownButton<String>(
                key: const Key('campus-role-campus'),
                isExpanded: true,
                value: _campus,
                hint: const Text('Choose a campus'),
                items: [
                  for (final c in _campusOptions)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _campus = v),
              ),
            ),
            Semantics(
              label: 'Role',
              child: DropdownButton<String>(
                key: const Key('campus-role-role'),
                isExpanded: true,
                value: _role,
                items: [
                  for (final e in _roleOptions)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _role = v ?? _role),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            AppButton(
              key: const Key('campus-role-add'),
              label: _busy ? 'Saving…' : 'Add role',
              fullWidth: true,
              onPressed: _busy || _campus == null
                  ? null
                  : () {
                      final campus = widget.campuses.firstWhere(
                        (c) => c.id == _campus,
                      );
                      _run(
                        () => widget.repository.grantCampusRole(
                          widget.userId,
                          campusId: _campus!,
                          role: _role,
                        ),
                        '${campusRoleLabels[_role]} added at ${campus.name}.',
                      );
                    },
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'The person must already work at that campus. Campus admins can grant only '
              'teacher and attendance roles on their own campus.',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

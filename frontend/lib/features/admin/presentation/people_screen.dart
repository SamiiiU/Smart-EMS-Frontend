import 'package:flutter/material.dart';

import '../../../core/shell/campus_context.dart';
import '../../../core/shell/identity_resolver.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/keyboard_tap_target.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/admin_repository.dart';
import '../domain/people_models.dart';
import 'campus_roles_sheet.dart';

/// Accounts: every staff member, student and parent, and whether each one
/// can actually sign in.
///
/// Built on request (2026-09-23) after a created user was invisible
/// everywhere in the app. The question this screen answers is the one an
/// admin actually asks — "has this person got a login yet?" — which nothing
/// else could answer.
///
/// **What it cannot show.** There is no endpoint that lists logins
/// (`GET /api/users` does not exist). Everything here comes from person
/// records, so a login created without a linked record appears nowhere. The
/// screen says so rather than implying the list is complete.
///
/// Search is client-side (B-02) and parents are assembled per student
/// (no guardians list endpoint) — both documented on `loadPeople`. The server
/// already scopes the lists: staff to the caller's `staff.manage` campuses,
/// students to its `student.view` campuses.
///
/// M5: the list is the shared [AdaptiveDataView] (table on wide screens, cards
/// on phones). "Campus roles" is a row action, kept outside the row's tap
/// target; rows do not navigate.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    required this.repository,
    this.currentIdentity,
    super.key,
  });

  final AdminRepository repository;

  /// The signed-in account, for showing "Campus roles" only where the server
  /// would allow it (ADR-011, CampusGrantService). Optional: when absent or
  /// when permissions are unknown, the action is offered and the server
  /// decides, exactly as before. Hiding is never authorization.
  final IdentityResult? Function()? currentIdentity;

  @override
  State<PeopleScreen> createState() => PeopleScreenState();
}

/// What a viewer may offer in the Campus roles sheet, from the same server
/// rule: institution-wide managers — no restriction (null); a campus admin —
/// teacher/attendance staff on its own user.manage campuses. Null when the
/// identity is unknown (the server decides, as before).
({Set<String>? roles, Set<String>? campusIds}) campusRolePolicy(
  IdentityResult? identity,
) {
  if (identity == null || !identity.permissionsKnown) {
    return (roles: null, campusIds: null);
  }
  const institutionWideRoles = {
    'owner',
    'institution_owner',
    'admin',
    'institution_admin',
    'super_admin',
  };
  if (identity.grants.any(
    (g) => g.campusId == null && institutionWideRoles.contains(g.role),
  )) {
    return (roles: null, campusIds: null);
  }
  final campuses = {
    for (final g in identity.grants)
      if (g.role == 'campus_admin' &&
          g.campusId != null &&
          g.permissions.contains('user.manage'))
        g.campusId!,
  };
  return (roles: const {'teacher', 'attendance_staff'}, campusIds: campuses);
}

/// Mirrors the server's rule for administering campus grants
/// (CampusGrantService.manager/list): an institution-wide owner/admin grant,
/// or a campus_admin grant that carries `user.manage` for its campus. Null
/// when it cannot be known (no identity, or permissions not loaded).
bool? canAdministerCampusRoles(IdentityResult? identity) {
  if (identity == null || !identity.permissionsKnown) return null;
  const institutionWideRoles = {
    'owner',
    'institution_owner',
    'admin',
    'institution_admin',
    'super_admin',
  };
  return identity.grants.any(
    (g) =>
        (g.campusId == null && institutionWideRoles.contains(g.role)) ||
        (g.role == 'campus_admin' &&
            g.campusId != null &&
            g.permissions.contains('user.manage')),
  );
}

class PeopleScreenState extends State<PeopleScreen> {
  ScreenState<PeopleDirectory> _state =
      const ScreenState<PeopleDirectory>.loading();

  PeopleGroup _group = PeopleGroup.staff;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(
      () =>
          _state = ScreenState<PeopleDirectory>.loading(previous: _state.data),
    );
    try {
      final people = await widget.repository.loadPeople();
      if (!mounted) return;
      setState(
        () => _state = ScreenState<PeopleDirectory>.data(
          people,
          isEmpty: people.isEmpty,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      final failure = e is LoadFailure ? e : const LoadFailure();
      setState(
        () => _state = ScreenState<PeopleDirectory>.failed(
          failure,
          cached: _state.data,
          connection: failure.unreachable
              ? NetworkStatus.offline
              : NetworkStatus.online,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final data = _state.data;
    final filtering = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The header must never steal the list's space, and must not
            // overflow when there is little height (a short window, a phone
            // in landscape, or a large text scale — it overflowed by 9px at
            // 800×600 the first time). Flexible caps it at what is
            // available; the scroll view absorbs the rest.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageHeader(
                      title: 'Accounts',
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      data == null
                          ? 'Who is on the system, and who can sign in.'
                          : '${data.withoutLogin} of '
                                '${data.staff.length + data.students.length + data.parents.length} '
                                'people have no login yet.',
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    // M5: chips at their natural width (they had stretched to
                    // the full page width), one keyboard stop each.
                    Wrap(
                      spacing: AppSpacing.space3,
                      runSpacing: AppSpacing.space3,
                      children: [
                        for (final g in PeopleGroup.values)
                          _GroupChip(
                            key: Key('people-group-${g.name}'),
                            label: data == null
                                ? g.label
                                : '${g.label} · ${data.of(g).length}',
                            semanticLabel: g.label,
                            selected: g == _group,
                            onTap: () => setState(() => _group = g),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    AppTextField(
                      label: 'Search',
                      value: _query,
                      placeholder: 'Name, code or class',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ScreenStateBuilder<PeopleDirectory>(
                state: filtering && data != null
                    ? ScreenState<PeopleDirectory>.data(
                        data,
                        hasFilter: true,
                        isEmpty: _visible(data).isEmpty,
                      )
                    : _state,
                onRetry: _load,
                emptyTitle: 'Nobody yet',
                emptyMessage:
                    'Import students or create a user to get started.',
                emptyIcon: Icons.badge_outlined,
                filterDescription: filtering ? 'matching “$_query”' : null,
                onClearFilter: filtering
                    ? () => setState(() => _query = '')
                    : null,
                data: (context, loaded) => _list(context, loaded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PersonAccount> _visible(PeopleDirectory d) =>
      d.of(_group).where((p) => p.matches(_query)).toList()
        // Missing logins first: they are the rows that need doing something
        // about, which is the same reasoning as D-15 on the dashboard.
        ..sort((a, b) {
          if (a.hasLogin != b.hasLogin) return a.hasLogin ? 1 : -1;
          return a.fullName.compareTo(b.fullName);
        });

  /// Campus roles is offered for staff logins, never on the viewer's own row
  /// (the server refuses self-changes), and only when the viewer may
  /// administer campus grants — unless that cannot be known, in which case
  /// the server decides (as before).
  bool _offerCampusRoles(PersonAccount p) {
    if (p.group != PeopleGroup.staff || p.userId == null) return false;
    final viewer = widget.currentIdentity?.call();
    if (viewer?.userId != null && viewer!.userId == p.userId) return false;
    return canAdministerCampusRoles(viewer) ?? true;
  }

  Widget _list(BuildContext context, PeopleDirectory data) {
    final t = context.tokens;
    final rows = _visible(data);
    final idLabel = _group == PeopleGroup.students ? 'Admission no.' : 'Code';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_group == PeopleGroup.parents && data.parentsPartial) ...[
            const InlineAlert(
              tone: InlineAlertTone.warning,
              message:
                  'Some parents could not be loaded, so this list may be '
                  'incomplete. Reopen this tab to try again.',
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
          Expanded(
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.space6),
                    child: Text(
                      'No ${_group.label.toLowerCase()} to show.',
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  )
                : AdaptiveDataView<PersonAccount>(
                    rows: rows,
                    padding: EdgeInsets.zero,
                    semanticLabel: (p) => [
                      p.fullName.isEmpty ? 'Unnamed' : p.fullName,
                      if (p.identifier != null && p.identifier!.isNotEmpty)
                        p.identifier!,
                      if (p.detail != null && p.detail!.isNotEmpty) p.detail!,
                      p.hasLogin ? 'has login' : 'no login',
                    ].join(', '),
                    columns: [
                      DataColumnSpec(
                        label: 'Name',
                        value: (p) =>
                            p.fullName.isEmpty ? 'Unnamed' : p.fullName,
                        flex: 3,
                      ),
                      if (_group != PeopleGroup.parents)
                        DataColumnSpec(
                          label: idLabel,
                          value: (p) =>
                              p.identifier == null || p.identifier!.isEmpty
                              ? '—'
                              : p.identifier!,
                          flex: 2,
                        ),
                      DataColumnSpec(
                        label: 'Details',
                        value: (p) => p.detail == null || p.detail!.isEmpty
                            ? '—'
                            : p.detail!,
                        flex: 3,
                      ),
                      DataColumnSpec(
                        label: 'Login',
                        value: (p) => p.hasLogin ? 'Has login' : 'No login',
                        flex: 2,
                        cell: (p) => _LoginPill(hasLogin: p.hasLogin),
                      ),
                    ],
                    actionsFlex: 2,
                    rowActions: [
                      // Overhaul: campus roles for staff logins (ADR-011 delegation).
                      RowAction<PersonAccount>(
                        label: 'Campus roles',
                        icon: Icons.admin_panel_settings_outlined,
                        variant: AppButtonVariant.ghost,
                        key: (p) => Key('campus-roles-${p.id}'),
                        semanticLabel: (p) => 'Campus roles for ${p.fullName}',
                        isVisible: _offerCampusRoles,
                        // The screen does no processing here: the label must not
                        // read "Campus roles…" while the sheet is open.
                        isLoading: (_) => false,
                        onPressed: (p) {
                          final policy = campusRolePolicy(
                            widget.currentIdentity?.call(),
                          );
                          return showCampusRolesSheet(
                            context,
                            repository: widget.repository,
                            userId: p.userId!,
                            personName: p.fullName,
                            campuses:
                                CampusScope.maybeOf(context)?.options ??
                                const [],
                            allowedRoles: policy.roles,
                            allowedCampusIds: policy.campusIds,
                          );
                        },
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.space4),
          // Said once, at the bottom, rather than as a warning on every row:
          // it is a property of the whole list, not of any person in it.
          Text(
            'Logins that were never linked to a person cannot be listed — the '
            'system has no way to list them.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space6),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Keyboard-operable with selected state (same wrapper as the shell).
    return KeyboardTapTarget(
      label: semanticLabel,
      selected: selected,
      onTap: onTap,
      borderRadius: AppRadius.full,
      // No Container.alignment: it expands to the full offered width (the
      // chips stretched across the page). Align with width/height factors 1
      // centres the label while the chip keeps its natural width.
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizing.touchTargetMin),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
        decoration: BoxDecoration(
          color: selected ? t.primarySubtle : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? t.primaryAccent : t.border,
            width: AppSizing.borderThin,
          ),
        ),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            style: AppTypography.fieldLabel.copyWith(
              color: selected ? t.textPrimary : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The answer to the screen's real question, on every row.
class _LoginPill extends StatelessWidget {
  const _LoginPill({required this.hasLogin});

  final bool hasLogin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = hasLogin ? t.successBg : t.warningBg;
    final fg = hasLogin ? t.successTextOnBg : t.warningTextOnBg;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        hasLogin ? 'Has login' : 'No login',
        style: AppTypography.overline.copyWith(color: fg),
      ),
    );
  }
}

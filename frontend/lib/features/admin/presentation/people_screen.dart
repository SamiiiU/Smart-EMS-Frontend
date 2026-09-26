import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../data/admin_repository.dart';
import '../domain/people_models.dart';

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
/// (no guardians list endpoint) — both documented on `loadPeople`.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<PeopleScreen> createState() => PeopleScreenState();
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
                    Text(
                      'Accounts',
                      style: AppTypography.screenTitle.copyWith(
                        color: t.textPrimary,
                      ),
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
                    Wrap(
                      spacing: AppSpacing.space3,
                      runSpacing: AppSpacing.space3,
                      children: [
                        for (final g in PeopleGroup.values)
                          _GroupChip(
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

  Widget _list(BuildContext context, PeopleDirectory data) {
    final rows = _visible(data);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
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
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space6),
            child: Text(
              'No ${_group.label.toLowerCase()} to show.',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: context.tokens.textSecondary,
              ),
            ),
          ),
        for (final person in rows) _PersonRow(person: person),
        const SizedBox(height: AppSpacing.space6),
        // Said once, at the bottom, rather than as a warning on every row:
        // it is a property of the whole list, not of any person in it.
        Text(
          'Logins that were never linked to a person cannot be listed — the '
          'system has no way to list them.',
          style: AppTypography.bodyAdminMeta.copyWith(
            color: context.tokens.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizing.touchTargetMin,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
            decoration: BoxDecoration(
              color: selected ? t.primarySubtle : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: selected ? t.primaryAccent : t.border,
                width: AppSizing.borderThin,
              ),
            ),
            child: Text(
              label,
              style: AppTypography.fieldLabel.copyWith(
                color: selected ? t.textPrimary : t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final PersonAccount person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            person.fullName.isEmpty ? 'Unnamed' : person.fullName,
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          if (person.identifier != null && person.identifier!.isNotEmpty)
            Text(
              person.identifier!,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          if (person.detail != null && person.detail!.isNotEmpty)
            Text(
              person.detail!,
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          _LoginPill(hasLogin: person.hasLogin),
        ],
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

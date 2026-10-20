import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../admin/data/institution_admin_repository.dart';
import '../../admin/data/ownership_repository.dart';
import '../../admin/presentation/institution_admins_screen.dart';
import '../../admin/presentation/ownership_transfer_screen.dart';
import '../../auth/presentation/change_password_screen.dart';
import '../../auth/presentation/mfa_screen.dart';
import '../../../core/shell/campus_context.dart';
import '../../../core/shell/workspace_scope.dart';
import '../../../core/widgets/page_header.dart';

/// The "More" destination (D-27's mandatory fourth tab).
///
/// Sign-out, plus the appearance choice. It exists because sign-out
/// previously lived in the desktop sidebar footer, which does not render
/// below 600px — so a phone user, which is most teachers, had no way to sign
/// out at all.
///
/// Appearance was added on request (2026-09-23): the app followed the device
/// setting only, which a person on a device set to light mode cannot
/// override, however dim the classroom.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.onSignOut,
    this.institutionCode,
    this.userLabel,
    this.themeController,
    super.key,
  });

  final Future<void> Function() onSignOut;

  /// Null in tests and anywhere the appearance section is not wanted; the
  /// section is then simply absent rather than inert.
  final ThemeController? themeController;

  /// The institution CODE, not a display name — no endpoint returns a name
  /// (see BACKEND_CONTRACT.md). Showing the code is honest.
  final String? institutionCode;
  final String? userLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          // M1: a readable column on wide screens instead of full-width
          // buttons stretched across 1440 px.
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PageHeader(title: 'More', padding: EdgeInsets.zero),
                  const SizedBox(height: AppSpacing.space6),
                  if (userLabel != null) ...[
                    Text(
                      userLabel!,
                      style: AppTypography.personName.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                  ],
                  if (institutionCode != null) ...[
                    Text(
                      institutionCode!,
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                  ],
                  if (themeController != null)
                    _SettingsSection(
                      title: 'Display',
                      children: [_ThemeChoice(controller: themeController!)],
                    ),
                  if (CampusScope.maybeOf(context) case final campus?
                      when campus.options.length > 1 || campus.allowAllCampuses)
                    _SettingsSection(
                      title: 'Campus',
                      children: [
                        // Only campuses granted to this account (server-listed);
                        // "All Campuses" only for institution-wide authority.
                        Semantics(
                          label: 'Campus',
                          child: DropdownButton<String?>(
                            key: const Key('campus-switcher'),
                            isExpanded: true,
                            value: campus.selectedId,
                            hint: const Text('Choose a campus'),
                            items: [
                              if (campus.allowAllCampuses)
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All campuses'),
                                ),
                              for (final option in campus.options)
                                DropdownMenuItem<String?>(
                                  value: option.id,
                                  child: Text(option.name),
                                ),
                            ],
                            onChanged: (id) {
                              if (id != null || campus.allowAllCampuses) {
                                campus.select(id);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  _SettingsSection(
                    title: 'Security and access',
                    children: [
                      if (WorkspaceScope.maybeOf(context) case final ws?) ...[
                        AppButton(
                          key: const Key('settings-switch-workspace'),
                          label: ws.switchLabel,
                          variant: AppButtonVariant.secondary,
                          fullWidth: true,
                          icon: Icons.swap_horiz_outlined,
                          onPressed: ws.onSwitch,
                        ),
                        const SizedBox(height: AppSpacing.space3),
                      ],
                      if (PasswordScope.maybeOf(context) case final pw?) ...[
                        AppButton(
                          key: const Key('settings-change-password'),
                          label: 'Change password',
                          variant: AppButtonVariant.secondary,
                          fullWidth: true,
                          icon: Icons.password_outlined,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (route) => ChangePasswordScreen(
                                repository: pw.repository,
                                // Every session was revoked: leave this page, then
                                // drop the identity so the router lands on login.
                                onChanged: () {
                                  Navigator.of(route).pop();
                                  pw.onChanged();
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space3),
                      ],
                      if (MfaScope.maybeOf(context) case final mfa?) ...[
                        AppButton(
                          key: const Key('settings-two-factor'),
                          label: 'Two-factor authentication',
                          variant: AppButtonVariant.secondary,
                          fullWidth: true,
                          icon: Icons.verified_user_outlined,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (route) => MfaScreen(
                                repository: mfa,
                                optionalEnrolment: true,
                                onVerified: () => Navigator.of(route).pop(),
                                onSignOut: onSignOut,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space3),
                      ],
                      if (MfaScope.maybeOf(context) case final mfa?)
                        OwnershipTransferEntry(
                          repository: OwnershipRepository(mfa.dio),
                        ),
                      if (MfaScope.maybeOf(context) case final mfa?)
                        InstitutionAdminsEntry(dio: mfa.dio),
                    ],
                  ),
                  _SettingsSection(
                    title: 'Account',
                    children: [
                      AppButton(
                        label: 'Sign out',
                        variant: AppButtonVariant.secondary,
                        fullWidth: true,
                        icon: Icons.logout_outlined,
                        onPressed: onSignOut,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// System / Light / Dark, as three buttons rather than an on-off switch.
///
/// A two-state switch cannot express "follow my device", which is the
/// default and the right answer for most people — a switch would silently
/// pin the app to one mode the first time it was touched.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller,
      builder: (context, mode, _) => Wrap(
        spacing: AppSpacing.space3,
        runSpacing: AppSpacing.space3,
        children: [
          for (final (value, label, icon) in const [
            (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          ])
            _ThemeOption(
              label: label,
              icon: icon,
              selected: mode == value,
              onTap: () => controller.set(value),
            ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizing.touchTargetMin,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
            decoration: BoxDecoration(
              color: selected ? t.primarySubtle : t.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: selected ? t.primaryAccent : t.border,
                width: AppSizing.borderThin,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: AppSizing.avatar24,
                  color: selected ? t.textPrimary : t.textSecondary,
                ),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  label,
                  style: AppTypography.fieldLabel.copyWith(
                    color: selected ? t.textPrimary : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Ownership transfer", shown only to the people it concerns (hard-QA BUG-QA-06).
///
/// Previously every signed-in user saw it (teachers included). Starting a
/// transfer needs an institution-wide owner grant; ACCEPTING one is open to
/// any active account the owner chose, so the entry is shown when either:
/// - `/auth/me` reports an owner/institution_owner grant with no campus, or
/// - `GET /api/institution/ownership-transfer` returns a transfer involving
///   this account (the server only returns its own).
/// Hidden while loading or on any failure; the server enforces both rules
/// regardless, so hiding can never grant anything.
class OwnershipTransferEntry extends StatefulWidget {
  const OwnershipTransferEntry({required this.repository, super.key});

  final OwnershipRepository repository;

  @override
  State<OwnershipTransferEntry> createState() => _OwnershipTransferEntryState();
}

class _OwnershipTransferEntryState extends State<OwnershipTransferEntry> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    var show = false;
    try {
      final me = await widget.repository.dio.get<Map<String, dynamic>>(
        '/auth/me',
      );
      final grants = (me.data?['grants'] as List?) ?? const [];
      show = grants.whereType<Map>().any(
        (g) =>
            const {'owner', 'institution_owner'}.contains(g['role']) &&
            g['campusId'] == null,
      );
    } on Object {
      show = false;
    }
    if (!show) {
      final pending = await widget.repository.pending();
      show = pending.transfer != null;
    }
    if (mounted && show) setState(() => _show = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: AppButton(
        key: const Key('settings-ownership'),
        label: 'Ownership transfer',
        variant: AppButtonVariant.secondary,
        fullWidth: true,
        icon: Icons.key_outlined,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                OwnershipTransferScreen(repository: widget.repository),
          ),
        ),
      ),
    );
  }
}

/// ADR-007 / Doc 21: shown only to the institution-wide Owner. The server still
/// refuses everyone else; this only avoids offering an action that would fail.
class InstitutionAdminsEntry extends StatefulWidget {
  const InstitutionAdminsEntry({required this.dio, super.key});

  final Dio dio;

  @override
  State<InstitutionAdminsEntry> createState() => _InstitutionAdminsEntryState();
}

class _InstitutionAdminsEntryState extends State<InstitutionAdminsEntry> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    var show = false;
    try {
      final me = await widget.dio.get<Map<String, dynamic>>('/auth/me');
      final grants = (me.data?['grants'] as List?) ?? const [];
      show = grants.whereType<Map>().any(
        (g) =>
            const {'owner', 'institution_owner'}.contains(g['role']) &&
            g['campusId'] == null,
      );
    } on Object {
      show = false;
    }
    if (mounted && show) setState(() => _show = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: AppButton(
        key: const Key('settings-institution-admins'),
        label: 'Institution Admins',
        variant: AppButtonVariant.secondary,
        fullWidth: true,
        icon: Icons.admin_panel_settings_outlined,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => InstitutionAdminsScreen(
              repository: InstitutionAdminRepository(widget.dio),
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled group of related settings (M1 page composition).
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Nothing to offer this account: no empty, titled card.
    if (children.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTypography.overline.copyWith(color: t.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              side: BorderSide(color: t.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

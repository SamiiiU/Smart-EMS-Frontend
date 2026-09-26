import 'package:flutter/material.dart';

import '../../features/admin/data/admin_repository.dart';
import '../../features/admin/data/import_repository.dart';
import '../../features/admin/data/user_wizard_repository.dart';
import '../../features/admin/domain/admin_models.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/create_user_wizard_screen.dart';
import '../../features/admin/presentation/csv_import_screen.dart';
import '../../features/admin/presentation/people_screen.dart';
import '../../features/academics/data/academics_repository.dart';
import '../../features/complaints/data/complaints_repository.dart';
import '../../features/complaints/presentation/admin_complaints_screen.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/staff_attendance/data/staff_attendance_repository.dart';
import '../../features/staff_attendance/presentation/staff_attendance_screen.dart';
import '../../features/academics/presentation/academics_home_screen.dart';
import '../../features/finance/data/finance_repository.dart';
import '../../features/finance/presentation/finance_home_screen.dart';
import '../../features/setup/data/setup_repository.dart';
import '../../features/setup/presentation/setup_home_screen.dart';
import '../../features/admin/presentation/student_profile_screen.dart';
import '../../features/admin/presentation/students_list_screen.dart';
import '../../features/parent/data/parent_repository.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../theme/theme_controller.dart';
import '../shell/nav_destination.dart';
import '../widgets/states/screen_state.dart';
import '../widgets/states/screen_state_builder.dart';

/// Admin destinations, wired to real screens.
///
/// Until now the admin fell through to the teacher list, which is why an
/// admin signing in saw a Today tab built for someone else's job. The four
/// tabs here are the ones T10 actually built; nothing is stubbed, because a
/// tab that opens onto a placeholder is the false affordance D-19 forbids.
List<NavDestination> buildAdminDestinations({
  required AdminRepository admin,
  required UserWizardRepository wizard,
  required ImportRepository import,
  required ParentRepository parent,
  required SetupRepository setup,
  required FinanceRepository finance,
  required AcademicsRepository academics,
  required ComplaintsRepository complaints,
  required NotificationsRepository notifications,
  required StaffAttendanceRepository staffAttendance,
  required Future<void> Function() onSignOut,
  required String? institutionCode,
  ThemeController? themeController,
}) {
  return [
    NavDestination(
      id: 'dashboard',
      group: 'Overview',
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      route: '/dashboard',
      builder: (context) => AdminDashboardScreen(
        repository: admin,
        // Pushed as a route rather than switching tabs: the shell owns tab
        // selection and a tab cannot change it from inside. Back returns
        // to the dashboard, which is what the checklist implies.
        onOpenSetup: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SetupHomeScreen(setup: setup, admin: admin),
          ),
        ),
      ),
    ),
    NavDestination(
      id: 'students',
      group: 'Overview',
      label: 'Students',
      icon: Icons.groups_outlined,
      route: '/students',
      builder: (context) => _StudentsFlow(admin: admin, parent: parent),
    ),
    NavDestination(
      id: 'setup',
      group: 'School',
      label: 'Setup',
      icon: Icons.tune_outlined,
      route: '/setup',
      builder: (context) => SetupHomeScreen(setup: setup, admin: admin),
    ),
    NavDestination(
      id: 'fees',
      group: 'School',
      label: 'Fees',
      icon: Icons.payments_outlined,
      route: '/fees',
      builder: (context) => FinanceHomeScreen(
        finance: finance,
        setup: setup,
        admin: admin,
      ),
    ),
    NavDestination(
      id: 'academics',
      group: 'School',
      label: 'Academics',
      icon: Icons.school_outlined,
      route: '/academics',
      builder: (context) => AcademicsHomeScreen(
        academics: academics,
        setup: setup,
        admin: admin,
      ),
    ),
    NavDestination(
      id: 'complaints',
      group: 'Operations',
      label: 'Complaints',
      icon: Icons.forum_outlined,
      route: '/complaints',
      builder: (context) => AdminComplaintsScreen(
        repository: complaints,
        admin: admin,
      ),
    ),
    NavDestination(
      id: 'staff_attendance',
      group: 'Operations',
      label: 'Staff attendance',
      icon: Icons.co_present_outlined,
      route: '/staff-attendance',
      builder: (context) => StaffAttendanceScreen(repository: staffAttendance),
    ),
    NavDestination(
      id: 'notifications',
      group: 'Operations',
      label: 'Notifications',
      icon: Icons.notifications_none,
      route: '/notifications',
      builder: (context) => NotificationsScreen(repository: notifications),
    ),
    NavDestination(
      id: 'people',
      group: 'People',
      label: 'Accounts',
      icon: Icons.badge_outlined,
      route: '/accounts',
      builder: (context) => PeopleScreen(repository: admin),
    ),
    NavDestination(
      id: 'add_user',
      group: 'People',
      label: 'Add user',
      icon: Icons.person_add_alt_outlined,
      route: '/add-user',
      builder: (context) => _WizardLoader(admin: admin, wizard: wizard),
    ),
    NavDestination(
      id: 'import',
      group: 'People',
      label: 'Import',
      icon: Icons.upload_file_outlined,
      route: '/import',
      builder: (context) => CsvImportScreen(repository: import),
    ),
    NavDestination(
      id: 'more',
      label: 'More',
      icon: Icons.more_horiz,
      route: '/more',
      alwaysVisible: true,
      builder: (context) => SettingsScreen(
        onSignOut: onSignOut,
        institutionCode: institutionCode,
        themeController: themeController,
      ),
    ),
  ];
}

/// List → profile, as a local two-step.
///
/// Same shape as the teacher's `_TodayFlow`, for the same reason (D-30): the
/// tab keeps its own state, and back returns to the roster rather than
/// leaving the tab.
class _StudentsFlow extends StatefulWidget {
  const _StudentsFlow({required this.admin, required this.parent});

  final AdminRepository admin;
  final ParentRepository parent;

  @override
  State<_StudentsFlow> createState() => _StudentsFlowState();
}

class _StudentsFlowState extends State<_StudentsFlow> {
  AdminStudent? _selected;

  @override
  Widget build(BuildContext context) {
    final student = _selected;
    if (student == null) {
      return StudentsListScreen(
        repository: widget.admin,
        onOpenStudent: (s) => setState(() => _selected = s),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected = null);
      },
      child: StudentProfileScreen(
        student: student,
        parentRepository: widget.parent,
      ),
    );
  }
}

/// Resolves the campus the wizard writes into before showing it.
///
/// The wizard cannot open in a usable state without one — every person
/// record it creates carries a `campusId`. Showing the form first and
/// failing at the final step would waste the admin's whole entry, so the
/// lookup happens up front and its failure is a retryable screen state
/// rather than a dead form.
class _WizardLoader extends StatefulWidget {
  const _WizardLoader({required this.admin, required this.wizard});

  final AdminRepository admin;
  final UserWizardRepository wizard;

  @override
  State<_WizardLoader> createState() => _WizardLoaderState();
}

class _WizardLoaderState extends State<_WizardLoader> {
  ScreenState<List<String>> _state = const ScreenState<List<String>>.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() =>
        _state = ScreenState<List<String>>.loading(previous: _state.data));
    try {
      final ids = await widget.admin.loadCampusIds();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<String>>.data(ids));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _state = ScreenState<List<String>>.failed(
            e is LoadFailure ? e : const LoadFailure(),
            cached: _state.data,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenStateBuilder<List<String>>(
      state: _state,
      onRetry: _load,
      emptyTitle: 'No campus yet',
      emptyMessage: 'A campus has to exist before users can be created.',
      emptyIcon: Icons.apartment_outlined,
      data: (context, ids) => CreateUserWizardScreen(
        repository: widget.wizard,
        campusId: ids.first,
      ),
    );
  }
}

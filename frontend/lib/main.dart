import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/db/local_db.dart';
import 'core/network/api_client.dart';
import 'core/network/connectivity_sync_status_source.dart';
import 'core/network/network_identity_resolver.dart';
import 'core/network/token_store.dart';
import 'core/router/admin_destinations.dart';
import 'core/router/app_router.dart';
import 'core/router/auth_state.dart';
import 'core/router/teacher_destinations.dart';
import 'features/admin/data/admin_repository.dart';
import 'features/admin/data/import_repository.dart';
import 'features/admin/data/user_wizard_repository.dart';
import 'features/attendance/data/attendance_queue.dart';
import 'features/diary/data/diary_repository.dart';
import 'features/academics/data/academics_repository.dart';
import 'features/complaints/data/complaints_repository.dart';
import 'features/notifications/data/notifications_repository.dart';
import 'features/staff_attendance/data/staff_attendance_repository.dart';
import 'features/finance/data/finance_repository.dart';
import 'features/setup/data/setup_repository.dart';
import 'features/attendance/data/attendance_repository.dart';
import 'features/attendance/data/queue_sync_status_source.dart';
import 'features/parent/data/parent_repository.dart';
import 'features/timetable/data/timetable_repository.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/token_gallery.dart';
import 'core/theme/typography.dart';
import 'features/auth/data/auth_repository.dart';

/// Boots the design-system gallery instead of the app.
///
/// The gallery is a review artifact, not a screen — it is what the Netlify
/// deployment shows. Build it with:
///
/// ```
/// flutter build web --dart-define=GALLERY=true
/// ```
///
/// Default (false) is the real app: login, then the shell.
const bool _galleryMode = bool.fromEnvironment('GALLERY');

void main() {
  // Plus Jakarta Sans is bundled in assets/fonts/. Runtime fetching is OFF so
  // there is no network path for fonts at all: institutions are in
  // low-connectivity areas, and a cold offline first launch must still render
  // in the specified typeface rather than the platform fallback.
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const ProviderScope(child: SmartEmsApp()));
}

class SmartEmsApp extends StatefulWidget {
  const SmartEmsApp({super.key});

  @override
  State<SmartEmsApp> createState() => _SmartEmsAppState();
}

class _SmartEmsAppState extends State<SmartEmsApp> {
  // Built once, here, and shared: there is exactly one HTTP client in this
  // app, and the auth interceptor lives on it.
  static const TokenStore _tokenStore = SharedPreferencesTokenStore();
  late final _dio = buildApiClient(tokenStore: _tokenStore);
  late final _repository = AuthRepository(dio: _dio, tokenStore: _tokenStore);
  late final _identityResolver = NetworkIdentityResolver(_dio);
  late final _authState = AuthState(
    tokenStore: _tokenStore,
    identityResolver: _identityResolver,
    // Lets it fetch the institution's real display name for the app bar.
    dio: _dio,
  );
  // Offline attendance queue, on the PERSISTENT native executor (T8). This
  // is what makes a register survive the app being closed in a classroom
  // with no signal.
  late final _queue = AttendanceQueue(openConnection());
  late final _attendanceRepository =
      AttendanceRepository(dio: _dio, queue: _queue);
  late final _timetableRepository = TimetableRepository(_dio);
  late final _parentRepository = ParentRepository(_dio);
  // T10. The admin's student profile reuses the parent repository above
  // rather than a second copy of the same attendance call.
  late final _adminRepository = AdminRepository(_dio);
  late final _userWizardRepository = UserWizardRepository(_dio);
  late final _importRepository = ImportRepository(_dio);
  late final _diaryRepository = DiaryRepository(_dio);
  late final _setupRepository = SetupRepository(_dio);
  late final _financeRepository = FinanceRepository(_dio);
  late final _academicsRepository = AcademicsRepository(_dio);
  late final _complaintsRepository = ComplaintsRepository(_dio);
  late final _notificationsRepository = NotificationsRepository(_dio);
  late final _staffAttendanceRepository = StaffAttendanceRepository(_dio);
  // Device-level appearance preference (added 2026-09-23). Restored in
  // initState; until it resolves the app follows the device, which is also
  // the default, so there is no flash of the wrong theme.
  final _themeController = ThemeController();
  late final _syncStatusSource = QueueSyncStatusSource(
    connectivity: ConnectivitySyncStatusSource(),
    queue: _queue,
  );

  late final _router = buildRouter(
    authState: _authState,
    repository: _repository,
    syncStatusSource: _syncStatusSource,
    attendanceDestinations: (onSignOut, staffId, staffName) =>
        buildTeacherDestinations(
      diary: _diaryRepository,
      staffName: staffName,
      attendance: _attendanceRepository,
      timetable: _timetableRepository,
      // Resolved by NetworkIdentityResolver from GET /api/staff/me — the
      // SAME call it already made for the D-17 orphan check, not an extra
      // round trip. Still null for a role with no staff record (admin) or a
      // teacher/staff login that turned out notLinked; TodayScreen shows
      // its own empty state for that case rather than failing.
      staffId: staffId,
      onSignOut: onSignOut,
      institutionCode: _authState.institutionLabel,
      themeController: _themeController,
      complaints: _complaintsRepository,
      notifications: _notificationsRepository,
    ),
    parentDestinations: (onSignOut) => buildParentDestinations(
      parent: _parentRepository,
      onSignOut: onSignOut,
      institutionCode: _authState.institutionLabel,
      themeController: _themeController,
      complaints: _complaintsRepository,
      notifications: _notificationsRepository,
    ),
    studentDestinations: (onSignOut) => buildStudentDestinations(
      onSignOut: onSignOut,
      institutionCode: _authState.institutionLabel,
      themeController: _themeController,
      complaints: _complaintsRepository,
      notifications: _notificationsRepository,
    ),
    adminDestinations: (onSignOut) => buildAdminDestinations(
      admin: _adminRepository,
      setup: _setupRepository,
      finance: _financeRepository,
      academics: _academicsRepository,
      complaints: _complaintsRepository,
      notifications: _notificationsRepository,
      staffAttendance: _staffAttendanceRepository,
      wizard: _userWizardRepository,
      import: _importRepository,
      parent: _parentRepository,
      onSignOut: onSignOut,
      institutionCode: _authState.institutionLabel,
      themeController: _themeController,
    ),
  );

  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    // Gallery mode never touches the network, so it must not try to restore
    // a session — the design showcase has no backend and no origin on the
    // CORS allowlist.
    if (!_galleryMode) _authState.restore();
    _themeController.restore();
  }

  @override
  void dispose() {
    _authState.dispose();
    _themeController.dispose();
    super.dispose();
  }

  void _toggleBrightness() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Before identity resolves the app has no role, and the role only decides
    // a base body size (D-24). Teacher is the middle of the four sizes, so it
    // is the least-wrong stand-in for the login screen; AppShell applies the
    // real role once signed in. The gallery uses it for the same reason —
    // a display choice, NOT a product default.
    const preAuthRole = AppRole.teacher;

    // The gallery keeps its manual brightness toggle so both modes can be
    // compared side by side, and needs no router — it is one screen.
    if (_galleryMode) {
      return MaterialApp(
        title: 'Smart EMS',
        // The debug-build ribbon reads as part of the product in demos and
        // screenshots. Release builds never show it anyway, so hiding it
        // costs nothing and stops it being reported as a UI bug.
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode,
        theme: AppTheme.light(role: preAuthRole),
        darkTheme: AppTheme.dark(role: preAuthRole),
        home: TokenGalleryScreen(
          isDark: _themeMode == ThemeMode.dark,
          onToggleBrightness: _toggleBrightness,
        ),
      );
    }

    // Follows the device by default; More → Appearance overrides it, and
    // that choice is remembered across launches.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeController,
      builder: (context, themeMode, _) => MaterialApp.router(
        title: 'Smart EMS',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: AppTheme.light(role: preAuthRole),
        darkTheme: AppTheme.dark(role: preAuthRole),
        routerConfig: _router,
      ),
    );
  }
}

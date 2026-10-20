import 'package:dio/dio.dart';
import 'features/academy/data/academy_repository.dart';
import 'features/finance/data/payment_intent_store.dart';
import 'features/attendance/data/secure_attendance_queue.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/network/device_push_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/db/local_db.dart';
import 'core/network/api_client.dart';
import 'core/network/firebase_bootstrap.dart';
import 'core/network/connectivity_sync_status_source.dart';
import 'core/network/network_identity_resolver.dart';
import 'core/network/token_store.dart';
import 'core/network/secure_token_store.dart';
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
import 'features/attendance/data/attendance_sync_coordinator.dart';
import 'features/auth/data/remembered_institution.dart';
import 'features/parent/data/parent_repository.dart';
import 'features/timetable/data/timetable_repository.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/token_gallery.dart';
import 'core/theme/typography.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/mfa_repository.dart';
import 'core/shell/campus_context.dart';
import 'core/network/web_session.dart';
import 'core/network/campus_filter_interceptor.dart';
import 'core/network/browser/browser_bridge.dart';
import 'features/attendance/data/attendance_review_repository.dart';
import 'features/auth/presentation/change_password_screen.dart';
import 'features/auth/presentation/mfa_screen.dart';
import 'core/network/step_up_interceptor.dart';

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

  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SmartEmsApp()));
  if (!_galleryMode) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
    }
    unawaited(FirebaseBootstrap.initialize());
  }
}

class SmartEmsApp extends StatefulWidget {
  const SmartEmsApp({super.key});

  @override
  State<SmartEmsApp> createState() => _SmartEmsAppState();
}

class _SmartEmsAppState extends State<SmartEmsApp> with WidgetsBindingObserver {
  /// ADR-011: capabilities (roles, grants, campuses) refresh on app resume.
  /// No polling; the backend authorizes every request regardless.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _authState.isSignedIn &&
        !_authState.mfaPending) {
      _authState.refreshIdentity();
    }
  }

  // Built once, here, and shared: there is exactly one HTTP client in this
  // app, and the auth interceptor lives on it.
  // ADR-010: Android keeps credentials in the Keystore-backed vault; Web keeps
  // the access token in memory and the refresh token in an HttpOnly cookie.
  static final TokenStore _tokenStore = SerializedTokenStore(
    kIsWeb
        ? WebSessionTokenStore(
            hasCookieSession: () => readCookie('ems_csrf') != null,
          )
        : defaultTargetPlatform == TargetPlatform.android
        ? SecureTokenStore()
        : const SharedPreferencesTokenStore(),
  );
  // ADR-010 finance step-up and MFA_REQUIRED handling, on the same client.
  final _stepUp = StepUpInterceptor();
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final Dio _dio =
      buildApiClient(
          tokenStore: _tokenStore,
          web: kIsWeb,
          readCsrf: () => readCookie('ems_csrf'),
          crossTabLock: (action) => withCrossTabLock('ems-refresh', action),
        )
        ..interceptors.add(_stepUp)
        // ADR-011: list reads follow the selected campus; late answers are dropped.
        ..interceptors.add(
          CampusFilterInterceptor(selectedCampus: () => _campus.selectedId),
        );
  late final _mfaRepository = MfaRepository(_dio);
  late final CampusContext _campus = CampusContext(dio: _dio);
  late final _repository = AuthRepository(
    dio: _dio,
    tokenStore: _tokenStore,
    beforeLogout: () => _push.unregister(),
  );
  late final _identityResolver = NetworkIdentityResolver(_dio);
  late final _authState = AuthState(
    tokenStore: _tokenStore,
    identityResolver: _identityResolver,
    // Lets it fetch the institution's real display name for the app bar.
    dio: _dio,
    mfa: _mfaRepository,
    campus: _campus,
  );
  // Offline attendance queue, on the PERSISTENT native executor (T8). This
  // is what makes a register survive the app being closed in a classroom
  // with no signal.
  late final _queue = kIsWeb
      ? AttendanceQueue(openConnection())
      : SecureAttendanceQueue(
          openConnection(),
          owner: () {
            final identity = _authState.identity;
            final tenant = identity?.tenantId;
            final user = identity?.userId;
            return tenant == null || user == null ? null : '$tenant:$user';
          },
        );
  late final _attendanceRepository = AttendanceRepository(
    dio: _dio,
    queue: _queue,
  );
  late final _timetableRepository = TimetableRepository(_dio);
  late final _parentRepository = ParentRepository(_dio);
  // T10. The admin's student profile reuses the parent repository above
  // rather than a second copy of the same attendance call.
  late final _adminRepository = AdminRepository(_dio);
  late final _userWizardRepository = UserWizardRepository(_dio);
  late final _importRepository = ImportRepository(_dio);
  late final _diaryRepository = DiaryRepository(_dio);
  late final _setupRepository = SetupRepository(_dio);
  late final _financeRepository = FinanceRepository(
    _dio,
    intents: SecurePaymentIntentStore(),
    owner: () {
      final identity = _authState.identity;
      final tenant = identity?.tenantId, user = identity?.userId;
      return tenant == null || user == null ? null : '$tenant:$user';
    },
  );
  late final _academicsRepository = AcademicsRepository(_dio);
  late final _complaintsRepository = ComplaintsRepository(_dio);
  late final _push = DevicePushService(_authState, _dio);
  late final _notificationsRepository = NotificationsRepository(
    _dio,
    enablePush: _push.enable,
    disablePush: _push.disable,
    pushMessages: _push.messages,
  );
  late final _staffAttendanceRepository = StaffAttendanceRepository(_dio);
  // Academy Phase B (online-only; never uses the attendance queue).
  late final _academyRepository = AcademyRepository(_dio);
  // Device-level appearance preference (added 2026-09-23). Restored in
  // initState; until it resolves the app follows the device, which is also
  // the default, so there is no flash of the wrong theme.
  final _themeController = ThemeController();
  late final _syncStatusSource = QueueSyncStatusSource(
    connectivity: ConnectivitySyncStatusSource(),
    queue: _queue,
    accountChanges: _authState,
  );
  // F13: drains offline attendance on start/resume, reconnect, account change
  // and a backoff timer — not only right after a new register is submitted.
  late final _attendanceSync = AttendanceSyncCoordinator(
    repository: _attendanceRepository,
    queue: _queue,
    connectivity: _syncStatusSource,
    accountChanges: _authState,
  );

  late final _router = buildRouter(
    navigatorKey: _navigatorKey,
    attendanceQueue: _queue,
    authState: _authState,
    repository: _repository,
    syncStatusSource: _syncStatusSource,
    rememberedInstitution: const SharedPreferencesRememberedInstitution(),
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
          academy: _authState.academyEnabled ? _academyRepository : null,
          academics: _academicsRepository,
          campusChanges: _campus,
        ),
    parentDestinations: (onSignOut) => buildParentDestinations(
      parent: _parentRepository,
      academy: _authState.academyEnabled ? _academyRepository : null,
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
      parent: _parentRepository,
      academy: _authState.academyEnabled ? _academyRepository : null,
    ),
    academy: _academyRepository,
    adminDestinations: (onSignOut) => buildAdminDestinations(
      admin: _adminRepository,
      setup: _setupRepository,
      finance: _financeRepository,
      academics: _academicsRepository,
      complaints: _complaintsRepository,
      notifications: _notificationsRepository,
      staffAttendance: _staffAttendanceRepository,
      attendanceReviews: AttendanceReviewRepository(_dio),
      wizard: _userWizardRepository,
      import: _importRepository,
      parent: _parentRepository,
      onSignOut: onSignOut,
      currentIdentity: () => _authState.identity,
      institutionCode: _authState.institutionLabel,
      themeController: _themeController,
    ),
  );

  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Gallery mode never touches the network, so it must not try to restore
    // a session — the design showcase has no backend and no origin on the
    // CORS allowlist.
    if (!_galleryMode) {
      _push;
      _stepUp
        ..retryDio = _dio
        ..onMfaRequired = _authState.markMfaRequired
        ..prompt = (reason) async {
          final context = _navigatorKey.currentContext;
          if (context == null) return false;
          return showStepUpDialog(context, _mfaRepository, reason);
        };
      _authState.restore();
      if (!kIsWeb) _attendanceSync.start();
    }
    _themeController.restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_galleryMode) _push.dispose();
    if (!_galleryMode && !kIsWeb) _attendanceSync.dispose();
    _authState.dispose();
    _themeController.dispose();
    super.dispose();
  }

  void _toggleBrightness() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
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
        builder: (context, child) => MfaScope(
          repository: _mfaRepository,
          child: PasswordScope(
            repository: _repository,
            onChanged: _authState.clear,
            child: CampusScope(
              campus: _campus,
              child: child ?? const SizedBox(),
            ),
          ),
        ),
      ),
    );
  }
}

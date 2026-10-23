import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A campus the signed-in user may act in, with permissions from the grants
/// that cover THAT campus (`GET /api/campuses/mine`, ADR-011).
class CampusOption {
  const CampusOption({
    required this.id,
    required this.name,
    required this.permissions,
  });

  factory CampusOption.fromJson(Map json) => CampusOption(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    permissions: ((json['permissions'] as List?) ?? const [])
        .cast<String>()
        .toSet(),
  );

  final String id;
  final String name;
  final Set<String> permissions;
}

/// ADR-011 campus context. Owners/institution admins may choose "All
/// Campuses" (null) for overviews; everyone else only their granted
/// campuses. The last choice is remembered per institution + user on this
/// device and revalidated against the server on every load — a campus that
/// is no longer granted is cleared, never silently kept.
///
/// Mutations must use [requireCampus], which refuses All Campuses: a
/// campus-specific write is never inferred from first/last/all.
class CampusContext extends ChangeNotifier {
  CampusContext({
    required this.dio,
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Dio dio;
  final Future<SharedPreferences> Function() _prefs;

  List<CampusOption> _options = const [];
  bool _allowAll = false;
  String? _selected;
  String? _scopeKey;

  List<CampusOption> get options => _options;
  bool get allowAllCampuses => _allowAll;

  /// Null = All Campuses (only possible when [allowAllCampuses]).
  String? get selectedId => _selected;
  CampusOption? get selected =>
      _options.where((o) => o.id == _selected).firstOrNull;

  /// The explicit campus a campus-specific mutation must target.
  String requireCampus() {
    final id = _selected;
    if (id == null)
      throw StateError('Choose a specific campus before making this change.');
    return id;
  }

  /// Called at login, restore, resume and workspace switch.
  Future<void> load({
    required String? tenantId,
    required String? userId,
  }) async {
    if (tenantId == null || userId == null) return clear();
    final key = 'campus:$tenantId:$userId';
    final Response<dynamic> res;
    try {
      res = await dio.get<dynamic>('/api/campuses/mine');
    } on DioException {
      // Keep the previous context on a network failure; the server still
      // authorizes every request against the chosen campus.
      if (_scopeKey != key) clear();
      return;
    }
    final body = res.data is Map ? res.data as Map : const {};
    _options = [
      for (final c in (body['campuses'] as List?) ?? const [])
        if (c is Map) CampusOption.fromJson(c),
    ];
    _allowAll = body['allCampuses'] == true;
    _scopeKey = key;
    final prefs = await _prefs();
    final saved = prefs.getString(key);
    if (saved != null && _options.any((o) => o.id == saved)) {
      _selected = saved;
    } else {
      if (saved != null) await prefs.remove(key); // revoked: forget it
      // Only an unambiguous single campus is preselected; otherwise the user
      // chooses (never the first/last campus by accident).
      _selected = !_allowAll && _options.length == 1
          ? _options.single.id
          : null;
    }
    notifyListeners();
  }

  Future<void> select(String? campusId) async {
    if (campusId == null
        ? !_allowAll
        : !_options.any((o) => o.id == campusId)) {
      throw StateError('That campus is not available to this account.');
    }
    _selected = campusId;
    final key = _scopeKey;
    if (key != null) {
      final prefs = await _prefs();
      if (campusId == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, campusId);
      }
    }
    notifyListeners();
  }

  void clear() {
    _options = const [];
    _allowAll = false;
    _selected = null;
    _scopeKey = null;
    notifyListeners();
  }
}

/// Exposes the campus context to More (switcher) and any screen that needs
/// the chosen campus, rebuilding them when it changes.
class CampusScope extends InheritedNotifier<CampusContext> {
  const CampusScope({
    required CampusContext campus,
    required super.child,
    super.key,
  }) : super(notifier: campus);

  static CampusContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CampusScope>()?.notifier;
}

/// The campus a campus-specific MUTATION may target (ADR-011): the user's
/// explicit, still-authorized selection — or the only campus when there is
/// exactly one. Never the first/last of several, and never "All Campuses".
/// Null means the UI must ask the user to choose a campus first.
String? explicitCampusFor(BuildContext context, List<String> candidateIds) {
  final campus = CampusScope.maybeOf(context);
  final selected = campus?.selectedId;
  if (selected != null && candidateIds.contains(selected)) return selected;
  if (candidateIds.length == 1 &&
      (campus == null || campus.options.length <= 1)) {
    return candidateIds.single;
  }
  return null;
}

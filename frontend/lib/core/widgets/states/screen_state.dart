import 'package:flutter/widgets.dart';

/// The connectivity dimension of screen state. Kept separate from the async
/// value because a screen can be offline while holding perfectly good cached
/// data — the two are independent.
enum NetworkStatus { online, offline }

/// Why a load failed, when we can tell. Only [notLinked] changes the outcome;
/// everything else is an ordinary error.
enum LoadFailureKind {
  /// Anything the user might resolve by retrying.
  transient,

  /// 404 from `/api/staff/me` or `/api/students/me`. The login exists but was
  /// never linked to a person record — the D-17 orphan case. NOT an error, and
  /// retrying cannot fix it.
  notLinked,
}

/// A load failure, carrying the backend's own message where there is one.
@immutable
class LoadFailure {
  const LoadFailure({
    this.message,
    this.kind = LoadFailureKind.transient,
  });

  /// The backend's message, VERBATIM. Backend messages name the actual problem
  /// and often the next step; replacing them with "Something went wrong"
  /// discards that. Null when there genuinely is no message.
  final String? message;

  final LoadFailureKind kind;

  bool get isNotLinked => kind == LoadFailureKind.notLinked;
}

/// What a screen currently knows. Deliberately not `AsyncValue` from Riverpod:
/// the precedence rule turns on whether PRIOR DATA EXISTS, which Riverpod's
/// `AsyncValue` expresses as `hasValue` on a loading/error state — easy to
/// forget. Making it a named field of this type means it cannot be overlooked.
@immutable
class ScreenState<T> {
  const ScreenState({
    required this.status,
    this.data,
    this.failure,
    this.connection = NetworkStatus.online,
    this.hasFilter = false,
    this.isEmpty,
  });

  const ScreenState.loading({
    T? previous,
    NetworkStatus connection = NetworkStatus.online,
    bool hasFilter = false,
  }) : this(
          status: ScreenStatus.loading,
          data: previous,
          connection: connection,
          hasFilter: hasFilter,
        );

  const ScreenState.data(
    T value, {
    NetworkStatus connection = NetworkStatus.online,
    bool hasFilter = false,
    bool? isEmpty,
  }) : this(
          status: ScreenStatus.loaded,
          data: value,
          connection: connection,
          hasFilter: hasFilter,
          isEmpty: isEmpty,
        );

  const ScreenState.failed(
    LoadFailure failure, {
    T? cached,
    NetworkStatus connection = NetworkStatus.online,
    bool hasFilter = false,
  }) : this(
          status: ScreenStatus.error,
          data: cached,
          failure: failure,
          connection: connection,
          hasFilter: hasFilter,
        );

  final ScreenStatus status;

  /// Cached or previously-loaded data. Non-null means the user can already see
  /// rows, which changes the outcome for rows 2, 4 and 6 of the precedence
  /// rule (D-30).
  final T? data;

  final LoadFailure? failure;
  final NetworkStatus connection;

  /// Whether a filter is currently applied. Decides EmptyState vs
  /// FilteredEmptyState (D-14, and row 7 before row 8).
  final bool hasFilter;

  /// OVERRIDE for emptiness. Normally leave this null (D-39).
  ///
  /// [resolveOutcome] derives emptiness itself for the shapes that cover
  /// nearly every screen — anything `Iterable`, any `Map`, and any type
  /// implementing [HasRowCount] (which the paged result type will).
  ///
  /// Supply it only when `T` is a shape the resolver cannot inspect, e.g. a
  /// single profile object that is never "empty" (`isEmpty: false`). If `T` is
  /// not derivable and this is null, the resolver THROWS rather than guessing —
  /// see [derivedIsEmpty].
  final bool? isEmpty;

  bool get hasData => data != null;
  bool get isOffline => connection == NetworkStatus.offline;
}

enum ScreenStatus { loading, loaded, error }

/// Implemented by result types the resolver cannot inspect structurally — most
/// importantly the paged result type T6 will introduce.
///
/// Implementing this is what keeps `isEmpty` an override rather than a
/// per-screen obligation: the type answers once, and every screen using it
/// gets rows 7 and 8 for free.
abstract interface class HasRowCount {
  /// True when there are zero rows, regardless of page metadata.
  bool get isEmptyResult;
}

/// Derives emptiness for a loaded state (D-39).
///
/// The common case is automatic; the exotic case is LOUD.
///
/// Deliberately throws rather than defaulting to `false` when it cannot tell.
/// Defaulting to false is the dangerous branch: it silently skips rows 7 and 8
/// and renders a blank area with no explanation — which is precisely the
/// previous build's failure, where "no results" was indistinguishable from
/// "not loaded yet". Throwing surfaces the omission at first render, in
/// development, on the screen that forgot it.
bool derivedIsEmpty<T>(ScreenState<T> s) {
  final override = s.isEmpty;
  if (override != null) return override;

  final d = s.data;

  // Loaded with nothing at all is empty — there are no rows to show.
  if (d == null) return true;

  if (d is HasRowCount) return d.isEmptyResult;
  if (d is Iterable) return d.isEmpty;
  if (d is Map) return d.isEmpty;

  throw StateError(
    'ScreenState<$T> cannot derive emptiness (D-39).\n'
    '\n'
    'The resolver derives it for Iterable, Map, and any type implementing '
    'HasRowCount. `$T` is none of those, so rows 7 and 8 of the precedence '
    'rule cannot be evaluated.\n'
    '\n'
    'Fix one of these, do NOT ignore it:\n'
    '  - if `$T` is a paged result type, implement HasRowCount on it;\n'
    '  - if `$T` is a single object that is never empty (a profile, a '
    'settings record), pass isEmpty: false explicitly.\n'
    '\n'
    'This throws instead of assuming non-empty because assuming would render '
    'a blank area with no empty state and no explanation.',
  );
}

/// The single outcome a screen renders. Exactly one.
enum ScreenOutcome {
  offlineState,
  loadingSkeleton,
  errorState,
  filteredEmptyState,
  emptyState,
  unlinkedProfileState,

  /// The data itself — possibly with an offline indicator (row 2) or a
  /// non-blocking failure notice (row 6).
  data,
}

/// Resolves THE precedence rule. One implementation, so no screen decides for
/// itself — which is how the previous build ended up with a spinner on one
/// screen, a blank area on another, and "no results" indistinguishable from
/// "not loaded yet".
///
/// Evaluated in order:
///
/// | # | Condition | Renders |
/// |---|-----------|---------|
/// | 1 | offline, no cached data | `offlineState` |
/// | 2 | offline, cached data exists | `data` + offline indicator |
/// | 3 | loading, no prior data | `loadingSkeleton` |
/// | 4 | loading, prior data exists | `data`, refresh in background |
/// | 5 | error, no cached data | `errorState` |
/// | 6 | error, cached data exists | `data` + non-blocking failure notice |
/// | 7 | loaded, zero rows, filter active | `filteredEmptyState` |
/// | 8 | loaded, zero rows, no filter | `emptyState` |
/// | 9 | `/me` returned 404 | `unlinkedProfileState` |
/// | 10 | otherwise | `data` |
///
/// Rows 2, 4 and 6 are D-30: **existing data is never replaced by a state.** A
/// user who can already see rows does not lose them because a refresh failed or
/// the network dropped. Getting this wrong is what makes an app feel broken
/// rather than slow.
///
/// Row 9 is evaluated before rows 5/6 in practice, because a `notLinked`
/// failure is not an error and must not be offered a retry — it is checked as
/// part of the error branch rather than after it. The table's ordering is
/// preserved for every other case.
ScreenOutcome resolveOutcome<T>(ScreenState<T> s) {
  // 9 (within the failure branch): not an error, and retry cannot help.
  if (s.failure?.isNotLinked ?? false) {
    return ScreenOutcome.unlinkedProfileState;
  }

  // 1 & 2 — offline.
  if (s.isOffline) {
    return s.hasData ? ScreenOutcome.data : ScreenOutcome.offlineState;
  }

  // 3 & 4 — loading.
  if (s.status == ScreenStatus.loading) {
    return s.hasData ? ScreenOutcome.data : ScreenOutcome.loadingSkeleton;
  }

  // 5 & 6 — error.
  if (s.status == ScreenStatus.error) {
    return s.hasData ? ScreenOutcome.data : ScreenOutcome.errorState;
  }

  // 7 & 8 — loaded but empty. Filtered is checked FIRST (D-14).
  // Emptiness is DERIVED (D-39), not supplied: see [derivedIsEmpty].
  if (derivedIsEmpty(s)) {
    return s.hasFilter
        ? ScreenOutcome.filteredEmptyState
        : ScreenOutcome.emptyState;
  }

  // 10.
  return ScreenOutcome.data;
}

/// Whether the resolved outcome should also show the offline indicator
/// (row 2) or a non-blocking failure notice (row 6).
@immutable
class DataAdornment {
  const DataAdornment({
    required this.showOfflineIndicator,
    required this.showRefreshFailedNotice,
  });

  final bool showOfflineIndicator;
  final bool showRefreshFailedNotice;

  bool get any => showOfflineIndicator || showRefreshFailedNotice;
}

DataAdornment adornmentFor<T>(ScreenState<T> s) {
  final outcome = resolveOutcome(s);
  if (outcome != ScreenOutcome.data) {
    return const DataAdornment(
      showOfflineIndicator: false,
      showRefreshFailedNotice: false,
    );
  }
  return DataAdornment(
    showOfflineIndicator: s.isOffline,
    showRefreshFailedNotice:
        s.status == ScreenStatus.error && !s.isOffline && s.hasData,
  );
}

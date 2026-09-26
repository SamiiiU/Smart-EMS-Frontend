import 'package:dio/dio.dart';

import '../widgets/states/screen_state.dart';
import 'api_error_mapper.dart';

/// Adapts a Dio-backed request into [ScreenState] (D-40), so a repository
/// method can hand a [ScreenStateBuilder] something it consumes directly
/// instead of every feature screen hand-rolling its own try/catch.
///
/// [previous] is the last good [ScreenState] for this screen, if any — passed
/// through so rows 2/4/6 of the precedence rule (existing data survives a
/// failed refresh) work without the caller re-deriving them.
Future<ScreenState<T>> loadIntoScreenState<T>(
  Future<T> Function() request, {
  ScreenState<T>? previous,
  bool hasFilter = false,
  bool? isEmpty,
}) async {
  try {
    final data = await request();
    return ScreenState<T>.data(
      data,
      hasFilter: hasFilter,
      isEmpty: isEmpty,
    );
  } on DioException catch (err) {
    return ScreenState<T>.failed(
      mapDioError(err),
      cached: previous?.data,
      hasFilter: hasFilter,
    );
  }
}

import 'package:dio/dio.dart';

/// ADR-011 campus switcher for list reads. When a campus is selected, the
/// supported list endpoints are asked for that campus only (`campusId`); the
/// server can only NARROW to authorized campuses (404 otherwise). With no
/// selection ("All Campuses"), lists show every authorized campus.
///
/// A response for a campus that is no longer selected is rejected, so a late
/// answer can never populate the newly chosen campus.
class CampusFilterInterceptor extends Interceptor {
  CampusFilterInterceptor({required this.selectedCampus});

  final String? Function() selectedCampus;

  static const filteredPaths = {
    '/api/students',
    '/api/staff',
    '/api/sections',
    '/api/classes',
    '/api/academic-years',
    // Teacher Today course sessions (report 11 A-2).
    '/api/academy/sessions/mine',
  };
  static const _key = 'campusFilter';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'GET' && filteredPaths.contains(options.path)) {
      final campus = selectedCampus();
      options.extra[_key] = campus ?? '';
      if (campus != null && !options.queryParameters.containsKey('campusId')) {
        options.queryParameters = {...options.queryParameters, 'campusId': campus};
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final requested = response.requestOptions.extra[_key];
    if (requested is String && requested != (selectedCampus() ?? '')) {
      return handler.reject(DioException(
        requestOptions: response.requestOptions,
        type: DioExceptionType.cancel,
        error: 'Campus changed while loading; reload for the selected campus.',
      ));
    }
    handler.next(response);
  }
}
